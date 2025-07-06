// This file contains a _not working_ implementation of drawChar accelerated using arm neon.
#include <arm_neon.h>
#include <stddef.h>

// reMarkable 2 framebuffer constants
#define PACKED_PIXELS 8
#define REAL_WIDTH 1404
#define REAL_HEIGHT 1872
#define UPPER_MARGIN 8
#define LEFT_MARGIN 8
#define STRIDE 1408
#define DEPTH 2

void drawCharNeon(char* frame, size_t frame_len, char* bitmap_buffer, int bitmap_width, int bitmap_height, int x_offset, int y_offset, unsigned short phase) {
    const uint16_t phase_bits = phase;
    
    // Pre-compute phase pattern for 8 pixels (one word)
    const uint16_t phase_word = (phase_bits << 14) | (phase_bits << 12) | (phase_bits << 10) | (phase_bits << 8) |
                                (phase_bits << 6) | (phase_bits << 4) | (phase_bits << 2) | phase_bits;
    
    // NEON registers for vectorized operations
    const uint8x16_t zero_vec = vdupq_n_u8(0);
    const uint16x8_t phase_vec = vdupq_n_u16(phase_word);
    
    for (int y = 0; y < bitmap_height; y++) {
        const int buffer_y_pos = y + y_offset;
        if (buffer_y_pos < 0 || buffer_y_pos >= REAL_HEIGHT) continue;
        
        const int buffer_y = REAL_HEIGHT - buffer_y_pos - 1;
        const int row_offset = (UPPER_MARGIN + buffer_y) * STRIDE;
        
        int x = 0;
        const int bitmap_row_start = y * bitmap_width;
        
        // Process pixels word by word to maintain proper alignment
        while (x < bitmap_width) {
            const int buffer_x = x + x_offset;
            if (buffer_x < LEFT_MARGIN || buffer_x >= REAL_WIDTH) {
                x++;
                continue;
            }
            
            // Calculate how many pixels remain in the current word
            const int pixels_remaining_in_word = PACKED_PIXELS - (buffer_x % PACKED_PIXELS);
            const int pixels_to_process = (pixels_remaining_in_word < (bitmap_width - x)) ? 
                                         pixels_remaining_in_word : (bitmap_width - x);
            
            // Calculate word position using the actual buffer_x
            const int word_byte_pos = row_offset + (LEFT_MARGIN + buffer_x) / PACKED_PIXELS * DEPTH;
            
            if (word_byte_pos + 1 >= frame_len) {
                x += pixels_to_process;
                continue;
            }
            
            uint16_t* pixel_word = (uint16_t*)&frame[word_byte_pos];
            uint16_t word_value = *pixel_word;
            int changed = 0;
            
            // Process pixels in this word
            for (int px = 0; px < pixels_to_process; px++) {
                const int bitmap_index = bitmap_row_start + x + px;
                const uint8_t pixel_value = bitmap_buffer[bitmap_index];
                
                if (pixel_value != 0) {
                    const int pixel_pos = (buffer_x + px) % PACKED_PIXELS;
                    const int shift_amount = (PACKED_PIXELS - 1 - pixel_pos) * 2;
                    const uint16_t pixel_mask = ~(0x03 << shift_amount);
                    
                    word_value = (word_value & pixel_mask) | (phase_bits << shift_amount);
                    changed = 1;
                }
            }
            
            if (changed) {
                *pixel_word = word_value;
            }
            
            x += pixels_to_process;
        }
    }
}
