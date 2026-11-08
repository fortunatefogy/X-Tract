package com.example.linky;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;

import java.io.IOException;
import java.nio.ByteBuffer;

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
