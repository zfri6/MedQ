//============================================================================
// audio_mixer - Audio tone + PCM mixing with volume control
//
// Clock domain : clk_pix (25.000 MHz)
// Timing      : stb = 48 kHz gate
//
// Inputs:
//   tone_in : signed 16-bit from audio_tone_gen
//   pcm_in  : signed 16-bit from audio_pcm_player
//   volume  : 8-bit from param_bus.volume (0..255)
//
// Processing per stb:
//   1. Mix: mixed = tone_in + pcm_in (signed 17-bit to capture any overflow)
//   2. Scale by volume: scaled = mixed * volume >> 8
//   3. Saturate: clamp to signed 16-bit range [-32768, +32767]
//   4. Output: aud_l = aud_r = scaled (stereo, same value)
//
// The "same value" stereo is intentional: the physical speaker/HDMI
// carries mono content on both channels as per the MedQ design.
//
// Reference: doc/arch/interface_contract.yaml (frozen)
//============================================================================
`timescale 1ns / 1ps

module audio_mixer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stb,
    input  wire [15:0] tone_in,
    input  wire [15:0] pcm_in,
    input  wire [7:0]  volume,
    output reg  [15:0] aud_l,
    output reg  [15:0] aud_r
);

    //========================================================================
    // Audio mixing pipeline (purely combinational, registered on stb)
    //========================================================================
    // Step 1: mix tone + PCM (17-bit signed to capture any overflow)
    wire signed [16:0] mixed_17;
    assign mixed_17 = $signed({tone_in[15], tone_in}) + $signed({pcm_in[15], pcm_in});
    // mixed_17 range: [-65536, +65535]

    // Unsigned Q0.8 gain must be widened before signed multiplication.
    // Do not pre-shift the PCM: that cancels the required /256 attenuation.
    wire signed [25:0] product;
    assign product = mixed_17 * $signed({1'b0, volume});
    wire signed [31:0] scaled;
    assign scaled = product >>> 8;

    //========================================================================
    // Output: saturation + register on stb
    //========================================================================
    wire signed [15:0] mixed_out;

    // Saturation: clamp to signed 16-bit range [-32768, +32767]
    assign mixed_out = (scaled > 32'sd32767)  ? 16'sd32767  :
                       (scaled < -32'sd32768) ? 16'sd32768  :
                       scaled[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aud_l <= 16'd0;
            aud_r <= 16'd0;
        end else if (stb) begin
            aud_l <= mixed_out;
            aud_r <= mixed_out;  // Stereo: left=right (mono content)
        end
    end

endmodule
