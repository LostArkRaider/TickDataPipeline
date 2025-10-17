using TickDataPipeline

# Create state
state = create_tickhotloop_state()

# Configure for derivative encoder
encoder = "derivative"
derivative_scale = Float32(2.0)

# Process some test messages
tick_channel = stream_expanded_ticks("data/raw/YM 06-25.Last_100K.txt", 0.0)

for msg in tick_channel
    process_tick_signal!(
        msg, state,
        Float32(0.0625),  # agc_alpha
        Int32(4),         # agc_min_scale
        Int32(50),        # agc_max_scale
        Int32(10),        # winsorize_threshold
        Int32(40000),     # min_price
        Int32(43000),     # max_price
        Int32(50),        # max_jump
        encoder,          # "derivative"
        Float32(0.5),     # cpm_h (unused)
        derivative_scale  # tick_derivative_imag_scale
    )
    
    # Check output
    println("Tick $(msg.tick_idx): z = $(msg.complex_signal)")
    
    # Verify both real and imaginary can be positive and negative
    if msg.tick_idx > 10
        break
    end
end