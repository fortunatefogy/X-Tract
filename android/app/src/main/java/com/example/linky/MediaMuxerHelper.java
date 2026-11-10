package com.example.linky;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;

/** Merges a video-only stream and an audio-only stream without re-encoding. */
public final class MediaMuxerHelper {
    private static final int BUFFER_SIZE = 1024 * 1024;

    private MediaMuxerHelper() {}

    public static void mux(String videoPath, String audioPath, String outputPath)
            throws IOException {
        final MediaExtractor video = new MediaExtractor();
        final MediaExtractor audio = new MediaExtractor();
        MediaMuxer muxer = null;
        try {
            video.setDataSource(videoPath);
            audio.setDataSource(audioPath);

            final int videoTrack = firstTrack(video, "video/");
            final int audioTrack = firstTrack(audio, "audio/");
            if (videoTrack < 0) {
                throw new IOException("The video stream has no video track.");
            }
            if (audioTrack < 0) {
                throw new IOException("The audio stream has no audio track.");
            }

            final MediaFormat videoFormat = video.getTrackFormat(videoTrack);
            final MediaFormat audioFormat = audio.getTrackFormat(audioTrack);
            final boolean webm = outputPath.toLowerCase().endsWith(".webm");
            muxer = new MediaMuxer(
                    outputPath,
                    webm
                            ? MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM
                            : MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            final int videoOutputTrack;
            final int audioOutputTrack;
            try {
                videoOutputTrack = muxer.addTrack(videoFormat);
            } catch (Exception error) {
                throw new IOException(
                        "The device cannot mux the video track ("
                                + videoFormat.getString(MediaFormat.KEY_MIME)
                                + ") into "
                                + (webm ? "WebM" : "MP4"),
                        error);
            }
            try {
                audioOutputTrack = muxer.addTrack(audioFormat);
            } catch (Exception error) {
                throw new IOException(
                        "The device cannot mux the audio track ("
                                + audioFormat.getString(MediaFormat.KEY_MIME)
                                + ") into "
                                + (webm ? "WebM" : "MP4"),
                        error);
            }

            video.selectTrack(videoTrack);
            audio.selectTrack(audioTrack);
            muxer.start();
            copyTrack(video, muxer, videoOutputTrack);
            copyTrack(audio, muxer, audioOutputTrack);
            muxer.stop();
        } finally {
            try {
                video.release();
            } catch (Exception ignored) {
            }
            try {
                audio.release();
            } catch (Exception ignored) {
            }
            if (muxer != null) {
                try {
                    muxer.release();
                } catch (Exception ignored) {
                }
            }
        }
    }

    public static void remux(String inputPath, String outputPath) throws IOException {
        remuxInternal(inputPath, outputPath, false);
    }

    public static void extractAudio(String inputPath, String outputPath) throws IOException {
        remuxInternal(inputPath, outputPath, true);
    }

    private static void remuxInternal(
            String inputPath, String outputPath, boolean audioOnly) throws IOException {
        final MediaExtractor extractor = new MediaExtractor();
        MediaMuxer muxer = null;
        try {
            extractor.setDataSource(inputPath);
            final Map<Integer, Integer> outputTracks = new HashMap<>();
            final boolean webm = outputPath.toLowerCase().endsWith(".webm");
            muxer = new MediaMuxer(
                    outputPath,
                    webm
                            ? MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM
                            : MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            for (int index = 0; index < extractor.getTrackCount(); index++) {
                final MediaFormat format = extractor.getTrackFormat(index);
                final String mime = format.getString(MediaFormat.KEY_MIME);
                if (mime == null) {
                    continue;
                }
                final boolean audio = mime.toLowerCase().startsWith("audio/");
                final boolean video = mime.toLowerCase().startsWith("video/");
                if (audioOnly ? !audio : !(audio || video)) {
                    continue;
                }
                try {
                    final int outputTrack = muxer.addTrack(format);
                    outputTracks.put(index, outputTrack);
                    extractor.selectTrack(index);
                } catch (Exception ignored) {
                    // Skip tracks this device cannot write into the container.
                }
            }
            if (outputTracks.isEmpty()) {
                throw new IOException(
                        audioOnly
                                ? "The file has no audio track this device can extract."
                                : "The file has no audio or video track this device can remux.");
            }
            muxer.start();
            final ByteBuffer buffer = ByteBuffer.allocateDirect(BUFFER_SIZE);
            final MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (true) {
                final int track = extractor.getSampleTrackIndex();
                if (track < 0) {
                    break;
                }
                final Integer outputTrack = outputTracks.get(track);
                final int size = extractor.readSampleData(buffer, 0);
                if (size < 0) {
                    break;
                }
                if (outputTrack != null) {
                    info.offset = 0;
                    info.size = size;
                    info.presentationTimeUs = extractor.getSampleTime();
                    info.flags =
                            (extractor.getSampleFlags() & MediaExtractor.SAMPLE_FLAG_SYNC) != 0
                                    ? MediaCodec.BUFFER_FLAG_KEY_FRAME
                                    : 0;
                    muxer.writeSampleData(outputTrack, buffer, info);
                }
                extractor.advance();
            }
            muxer.stop();
        } finally {
            try {
                extractor.release();
            } catch (Exception ignored) {
            }
            if (muxer != null) {
                try {
                    muxer.release();
                } catch (Exception ignored) {
                }
            }
        }
    }

    private static int firstTrack(MediaExtractor extractor, String prefix) {
        for (int index = 0; index < extractor.getTrackCount(); index++) {
            final MediaFormat format = extractor.getTrackFormat(index);
            final String mime = format.getString(MediaFormat.KEY_MIME);
            if (mime != null && mime.toLowerCase().startsWith(prefix)) {
                return index;
            }
        }
        return -1;
    }

    private static void copyTrack(MediaExtractor extractor, MediaMuxer muxer, int track)
            throws IOException {
        final ByteBuffer buffer = ByteBuffer.allocateDirect(BUFFER_SIZE);
        final MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        while (true) {
            buffer.clear();
            final int size = extractor.readSampleData(buffer, 0);
            if (size < 0) {
                break;
            }
            info.offset = 0;
            info.size = size;
            info.presentationTimeUs = extractor.getSampleTime();
            info.flags = (extractor.getSampleFlags() & MediaExtractor.SAMPLE_FLAG_SYNC) != 0
                    ? MediaCodec.BUFFER_FLAG_KEY_FRAME
                    : 0;
            muxer.writeSampleData(track, buffer, info);
            extractor.advance();
        }
    }
}
