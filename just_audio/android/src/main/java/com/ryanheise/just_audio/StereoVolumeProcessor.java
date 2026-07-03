package com.ryanheise.just_audio;

import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.util.UnstableApi;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * An AudioProcessor that applies independent volume control to stereo channels.
 * Used to implement audio balance (left/right channel volume).
 */
@UnstableApi
public class StereoVolumeProcessor implements AudioProcessor {
    
    private static final int BYTES_PER_FRAME = 2; // 16-bit PCM
    
    private float leftVolume = 1.0f;
    private float rightVolume = 1.0f;
    
    private AudioFormat pendingInputAudioFormat;
    private AudioFormat pendingOutputAudioFormat;
    private AudioFormat inputAudioFormat;
    private AudioFormat outputAudioFormat;
    
    private ByteBuffer buffer;
    private ByteBuffer outputBuffer;
    private boolean inputEnded;
    
    public StereoVolumeProcessor() {
        buffer = EMPTY_BUFFER;
        outputBuffer = EMPTY_BUFFER;
        pendingInputAudioFormat = AudioFormat.NOT_SET;
        pendingOutputAudioFormat = AudioFormat.NOT_SET;
        inputAudioFormat = AudioFormat.NOT_SET;
        outputAudioFormat = AudioFormat.NOT_SET;
    }
    
    /**
     * Sets the volume for left and right channels.
     * @param leftVolume Volume for left channel (0.0 to 1.0)
     * @param rightVolume Volume for right channel (0.0 to 1.0)
     */
    public void setChannelVolumes(float leftVolume, float rightVolume) {
        this.leftVolume = leftVolume;
        this.rightVolume = rightVolume;
    }
    
    @NonNull
    @Override
    public AudioFormat configure(@NonNull AudioFormat inputAudioFormat) throws UnhandledAudioFormatException {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw new UnhandledAudioFormatException(inputAudioFormat);
        }
        
        // Only process stereo audio
        if (inputAudioFormat.channelCount != 2) {
            return AudioFormat.NOT_SET;
        }
        
        pendingInputAudioFormat = inputAudioFormat;
        pendingOutputAudioFormat = inputAudioFormat;
        return pendingOutputAudioFormat;
    }
    
    @Override
    public boolean isActive() {
        return pendingOutputAudioFormat != AudioFormat.NOT_SET
                && (leftVolume != 1.0f || rightVolume != 1.0f);
    }
    
    @Override
    public void queueInput(@NonNull ByteBuffer inputBuffer) {
        int position = inputBuffer.position();
        int limit = inputBuffer.limit();
        int size = limit - position;
        
        // If processor is inactive (no volume changes needed), pass through unchanged
        if (!isActive()) {
            outputBuffer = inputBuffer;
            return;
        }
        
        // Ensure buffer capacity
        if (buffer.capacity() < size) {
            buffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder());
        } else {
            buffer.clear();
        }
        
        // Process 16-bit PCM stereo samples
        while (position < limit) {
            // Read left channel sample
            short leftSample = inputBuffer.getShort(position);
            position += BYTES_PER_FRAME;
            
            // Read right channel sample
            short rightSample = inputBuffer.getShort(position);
            position += BYTES_PER_FRAME;
            
            // Apply volume to each channel
            short processedLeft = (short) (leftSample * leftVolume);
            short processedRight = (short) (rightSample * rightVolume);
            
            // Write processed samples
            buffer.putShort(processedLeft);
            buffer.putShort(processedRight);
        }
        
        inputBuffer.position(limit);
        buffer.flip();
        outputBuffer = buffer;
    }
    
    @NonNull
    @Override
    public ByteBuffer getOutput() {
        ByteBuffer outputBuffer = this.outputBuffer;
        this.outputBuffer = EMPTY_BUFFER;
        return outputBuffer;
    }
    
    @Override
    public boolean isEnded() {
        return inputEnded && outputBuffer == EMPTY_BUFFER;
    }
    
    @Override
    public void flush() {
        outputBuffer = EMPTY_BUFFER;
        inputEnded = false;
        inputAudioFormat = pendingInputAudioFormat;
        outputAudioFormat = pendingOutputAudioFormat;
    }
    
    @Override
    public void queueEndOfStream() {
        inputEnded = true;
    }
    
    @Override
    public void reset() {
        flush();
        buffer = EMPTY_BUFFER;
        pendingInputAudioFormat = AudioFormat.NOT_SET;
        pendingOutputAudioFormat = AudioFormat.NOT_SET;
        inputAudioFormat = AudioFormat.NOT_SET;
        outputAudioFormat = AudioFormat.NOT_SET;
    }
}
