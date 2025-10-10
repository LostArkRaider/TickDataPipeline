# Test CPM Configuration System
# Tests encoder parameter parsing, validation, and TOML round-trip
# Protocol T-36 compliant: NO string literals in @test or @testset

using Test
using TickDataPipeline

@testset begin  # CPM Configuration Tests

    @testset begin  # Default Configuration Has CPM Encoder
        config = create_default_config()
        @test config.signal_processing.encoder_type == "cpm"
        @test config.signal_processing.cpm_modulation_index == Float32(0.5)
        @test config.signal_processing.cpm_lut_size == Int32(1024)
    end

    @testset begin  # CPM Configuration Validation - Valid
        config = create_default_config()
        is_valid, errors = validate_config(config)
        @test is_valid == true
        @test isempty(errors)
    end

    @testset begin  # CPM Configuration with h=0.5
        sp = SignalProcessingConfig(encoder_type="cpm", cpm_modulation_index=Float32(0.5))
        @test sp.encoder_type == "cpm"
        @test sp.cpm_modulation_index == Float32(0.5)
        @test sp.cpm_lut_size == Int32(1024)
    end

    @testset begin  # CPM Configuration with h=0.25
        sp = SignalProcessingConfig(encoder_type="cpm", cpm_modulation_index=Float32(0.25))
        @test sp.encoder_type == "cpm"
        @test sp.cpm_modulation_index == Float32(0.25)
    end

    @testset begin  # HEXAD16 Configuration Backward Compatible
        sp = SignalProcessingConfig(encoder_type="hexad16")
        @test sp.encoder_type == "hexad16"
        # CPM parameters present but unused for hexad16
        @test sp.cpm_modulation_index == Float32(0.5)
        @test sp.cpm_lut_size == Int32(1024)
    end

    @testset begin  # Invalid Encoder Type Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="invalid")
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test length(errors) == 1
        @test occursin("encoder_type", errors[1])
    end

    @testset begin  # Invalid CPM Modulation Index h=0 Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="cpm",
                cpm_modulation_index=Float32(0.0)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test any(e -> occursin("cpm_modulation_index", e), errors)
    end

    @testset begin  # Invalid CPM Modulation Index h=1.5 Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="cpm",
                cpm_modulation_index=Float32(1.5)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test any(e -> occursin("cpm_modulation_index", e), errors)
    end

    @testset begin  # Invalid CPM LUT Size Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="cpm",
                cpm_lut_size=Int32(512)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test any(e -> occursin("cpm_lut_size", e), errors)
    end

    @testset begin  # HEXAD16 Config Validation Allows Any CPM Params
        # When encoder_type="hexad16", CPM parameters are ignored (no validation)
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="hexad16",
                cpm_modulation_index=Float32(999.0),  # Invalid if used, but ignored
                cpm_lut_size=Int32(999)                # Invalid if used, but ignored
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true  # CPM params not validated for hexad16
    end

    @testset begin  # TOML Round-Trip CPM Configuration
        # Create config with CPM encoder
        original = PipelineConfig(
            pipeline_name = "test_cpm",
            signal_processing = SignalProcessingConfig(
                encoder_type = "cpm",
                cpm_modulation_index = Float32(0.5),
                cpm_lut_size = Int32(1024)
            )
        )

        # Save to TOML
        temp_path = joinpath(tempdir(), "test_cpm_config.toml")
        save_config_to_toml(original, temp_path)

        # Load from TOML
        loaded = load_config_from_toml(temp_path)

        # Verify round-trip
        @test loaded.pipeline_name == "test_cpm"
        @test loaded.signal_processing.encoder_type == "cpm"
        @test loaded.signal_processing.cpm_modulation_index == Float32(0.5)
        @test loaded.signal_processing.cpm_lut_size == Int32(1024)

        # Clean up
        rm(temp_path, force=true)
    end

    @testset begin  # TOML Round-Trip HEXAD16 Configuration
        # Create config with HEXAD16 encoder
        original = PipelineConfig(
            pipeline_name = "test_hexad16",
            signal_processing = SignalProcessingConfig(encoder_type = "hexad16")
        )

        # Save to TOML
        temp_path = joinpath(tempdir(), "test_hexad16_config.toml")
        save_config_to_toml(original, temp_path)

        # Load from TOML
        loaded = load_config_from_toml(temp_path)

        # Verify round-trip
        @test loaded.pipeline_name == "test_hexad16"
        @test loaded.signal_processing.encoder_type == "hexad16"

        # Clean up
        rm(temp_path, force=true)
    end

    @testset begin  # Load CPM Example TOML File
        config_path = "C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline\\config\\example_cpm.toml"
        if isfile(config_path)
            config = load_config_from_toml(config_path)
            @test config.signal_processing.encoder_type == "cpm"
            @test config.signal_processing.cpm_modulation_index == Float32(0.5)
            @test config.signal_processing.cpm_lut_size == Int32(1024)
            is_valid, errors = validate_config(config)
            @test is_valid == true
        end
    end

    @testset begin  # Load HEXAD16 Example TOML File
        config_path = "C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline\\config\\example_hexad16.toml"
        if isfile(config_path)
            config = load_config_from_toml(config_path)
            @test config.signal_processing.encoder_type == "hexad16"
            is_valid, errors = validate_config(config)
            @test is_valid == true
        end
    end

    @testset begin  # CPM h=1.0 Maximum Valid Value
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="cpm",
                cpm_modulation_index=Float32(1.0)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true
    end

    @testset begin  # CPM h=0.0001 Minimum Valid Value
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="cpm",
                cpm_modulation_index=Float32(0.0001)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true
    end

end  # End CPM Configuration Tests
