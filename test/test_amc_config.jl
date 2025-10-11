# Test AMC Configuration System
# Tests AMC encoder parameter parsing, validation, and TOML round-trip
# Protocol T-36 compliant: NO string literals in @test or @testset

using Test
using TickDataPipeline

@testset begin  # AMC Configuration Tests

    @testset begin  # AMC Configuration Creation
        sp = SignalProcessingConfig(encoder_type="amc")
        @test sp.encoder_type == "amc"
        @test sp.amc_carrier_period == Float32(16.0)
        @test sp.amc_lut_size == Int32(1024)
    end

    @testset begin  # AMC Configuration Validation - Valid
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true
        @test isempty(errors)
    end

    @testset begin  # AMC Configuration with Custom Carrier Period
        sp = SignalProcessingConfig(
            encoder_type="amc",
            amc_carrier_period=Float32(32.0)
        )
        @test sp.encoder_type == "amc"
        @test sp.amc_carrier_period == Float32(32.0)
        @test sp.amc_lut_size == Int32(1024)
    end

    @testset begin  # AMC Configuration with Carrier Period 8 Ticks
        sp = SignalProcessingConfig(
            encoder_type="amc",
            amc_carrier_period=Float32(8.0)
        )
        @test sp.encoder_type == "amc"
        @test sp.amc_carrier_period == Float32(8.0)
    end

    @testset begin  # AMC Encoder Type Accepted by Validator
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true
        @test isempty(errors)
    end

    @testset begin  # Invalid AMC Carrier Period Zero Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="amc",
                amc_carrier_period=Float32(0.0)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test any(e -> occursin("amc_carrier_period", e), errors)
    end

    @testset begin  # Invalid AMC Carrier Period Negative Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="amc",
                amc_carrier_period=Float32(-16.0)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test any(e -> occursin("amc_carrier_period", e), errors)
    end

    @testset begin  # Invalid AMC LUT Size Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="amc",
                amc_lut_size=Int32(512)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test any(e -> occursin("amc_lut_size", e), errors)
    end

    @testset begin  # Invalid AMC LUT Size 2048 Rejected
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="amc",
                amc_lut_size=Int32(2048)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == false
        @test any(e -> occursin("amc_lut_size", e), errors)
    end

    @testset begin  # HEXAD16 Config Validation Allows Any AMC Params
        # When encoder_type="hexad16", AMC parameters are ignored (no validation)
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="hexad16",
                amc_carrier_period=Float32(-999.0),  # Invalid if used, but ignored
                amc_lut_size=Int32(999)               # Invalid if used, but ignored
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true  # AMC params not validated for hexad16
    end

    @testset begin  # CPM Config Validation Allows Any AMC Params
        # When encoder_type="cpm", AMC parameters are ignored (no validation)
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="cpm",
                amc_carrier_period=Float32(-999.0),  # Invalid if used, but ignored
                amc_lut_size=Int32(999)               # Invalid if used, but ignored
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true  # AMC params not validated for cpm
    end

    @testset begin  # TOML Round-Trip AMC Configuration
        # Create config with AMC encoder
        original = PipelineConfig(
            pipeline_name = "test_amc",
            signal_processing = SignalProcessingConfig(
                encoder_type = "amc",
                amc_carrier_period = Float32(16.0),
                amc_lut_size = Int32(1024)
            )
        )

        # Save to TOML
        temp_path = joinpath(tempdir(), "test_amc_config.toml")
        save_config_to_toml(original, temp_path)

        # Load from TOML
        loaded = load_config_from_toml(temp_path)

        # Verify round-trip
        @test loaded.pipeline_name == "test_amc"
        @test loaded.signal_processing.encoder_type == "amc"
        @test loaded.signal_processing.amc_carrier_period == Float32(16.0)
        @test loaded.signal_processing.amc_lut_size == Int32(1024)

        # Clean up
        rm(temp_path, force=true)
    end

    @testset begin  # TOML Round-Trip AMC with Custom Carrier Period
        # Create config with custom carrier period
        original = PipelineConfig(
            pipeline_name = "test_amc_custom",
            signal_processing = SignalProcessingConfig(
                encoder_type = "amc",
                amc_carrier_period = Float32(32.0),
                amc_lut_size = Int32(1024)
            )
        )

        # Save to TOML
        temp_path = joinpath(tempdir(), "test_amc_custom_config.toml")
        save_config_to_toml(original, temp_path)

        # Load from TOML
        loaded = load_config_from_toml(temp_path)

        # Verify round-trip
        @test loaded.pipeline_name == "test_amc_custom"
        @test loaded.signal_processing.encoder_type == "amc"
        @test loaded.signal_processing.amc_carrier_period == Float32(32.0)
        @test loaded.signal_processing.amc_lut_size == Int32(1024)

        # Clean up
        rm(temp_path, force=true)
    end

    @testset begin  # Load AMC Example TOML File
        config_path = "C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline\\config\\example_amc.toml"
        if isfile(config_path)
            config = load_config_from_toml(config_path)
            @test config.signal_processing.encoder_type == "amc"
            @test config.signal_processing.amc_carrier_period == Float32(16.0)
            @test config.signal_processing.amc_lut_size == Int32(1024)
            is_valid, errors = validate_config(config)
            @test is_valid == true
        end
    end

    @testset begin  # Load Default TOML with AMC Parameters
        config_path = "C:\\Users\\Keith\\source\\repos\\Julia\\TickDataPipeline\\config\\default.toml"
        if isfile(config_path)
            config = load_config_from_toml(config_path)
            # Default config should have AMC parameters present (even if encoder_type is not "amc")
            @test isdefined(config.signal_processing, :amc_carrier_period)
            @test isdefined(config.signal_processing, :amc_lut_size)
            @test config.signal_processing.amc_carrier_period == Float32(16.0)
            @test config.signal_processing.amc_lut_size == Int32(1024)
            is_valid, errors = validate_config(config)
            @test is_valid == true
        end
    end

    @testset begin  # AMC Carrier Period Minimum Valid Value
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="amc",
                amc_carrier_period=Float32(0.001)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true
    end

    @testset begin  # AMC Carrier Period Large Valid Value
        config = PipelineConfig(
            signal_processing = SignalProcessingConfig(
                encoder_type="amc",
                amc_carrier_period=Float32(1000.0)
            )
        )
        is_valid, errors = validate_config(config)
        @test is_valid == true
    end

    @testset begin  # AMC Configuration Coexists with CPM Parameters
        # Create config with AMC encoder (CPM parameters present but unused)
        sp = SignalProcessingConfig(
            encoder_type="amc",
            cpm_modulation_index=Float32(0.5),
            amc_carrier_period=Float32(16.0)
        )
        @test sp.encoder_type == "amc"
        @test sp.cpm_modulation_index == Float32(0.5)  # Present but unused for AMC
        @test sp.amc_carrier_period == Float32(16.0)
    end

    @testset begin  # All Three Encoders Validated by Validator
        # Test that all three encoder types are accepted
        config_amc = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="amc")
        )
        is_valid_amc, errors_amc = validate_config(config_amc)
        @test is_valid_amc == true

        config_cpm = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="cpm")
        )
        is_valid_cpm, errors_cpm = validate_config(config_cpm)
        @test is_valid_cpm == true

        config_hexad16 = PipelineConfig(
            signal_processing = SignalProcessingConfig(encoder_type="hexad16")
        )
        is_valid_hexad16, errors_hexad16 = validate_config(config_hexad16)
        @test is_valid_hexad16 == true
    end

end  # End AMC Configuration Tests
