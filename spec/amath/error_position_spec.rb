# frozen_string_literal: true

# Rejection positions must match Plurimath's Parslet parser: the deepest
# leaf of the tree of failures that caused the rejection, on either engine.
RSpec.describe Amath::ParseError do
  %i[native ruby].each do |engine|
    context "with engine: #{engine.inspect}" do
      before { require_native! if engine == :native }

      # Spike fixture: the number "1" succeeds through its DIGITS branch, so
      # the abandoned "1,<digit>" attempt (failing at byte 11) is not part of
      # the rejection; Parslet reports the "," at byte 10.
      it "ignores failures inside branches that later succeeded" do
        expect { Amath.parse("text(é) 1,", decimal: ",", engine: engine) }
          .to raise_error(described_class) { |e|
            expect([e.byte_offset, e.char_offset]).to eq([10, 9])
            expect(e.message).to include("character 9 (byte 10)")
          }
      end
    end
  end

  # The production AsciiMath grammar. Inputs are Plurimath-preprocessed text
  # (Amath.parse does not preprocess); expected characters are the Parslet
  # oracle's (Plurimath ae20be11, Parslet 2.0.0).
  describe "against the Parslet oracle" do
    artifact = ENV.fetch("AMATH_ARTIFACT", Amath::DEFAULT_ARTIFACT_PATH)

    # testsuite/asciimath/rejections.yaml, oracle-recorded for both markers.
    testsuite = {
      "a/" => 1, "/b" => 0, "/" => 0, "a / " => 2, "`" => 0, "right" => 0,
      "left( x right" => 13, "left{ x right}" => 8, "left| x right|" => 8,
      "ℒa/" => 2, "ℒxℛa/" => 4, "ᑕxᑐy/" => 4, "ℒaℛᑕbᑐc/" => 7
    }
    # Non-ASCII and valid-prefix edge cases, oracle-recorded for "." only.
    supplement = { "漢字`" => 2, "αβ /" => 3, "é/" => 1, "x+y `" => 4, "a+b right" => 4 }
    oracle = { "." => testsuite.merge(supplement), "," => testsuite }

    before do
      skip "set AMATH_ARTIFACT to the AsciiMath grammar artifact" unless File.file?(artifact)
      Amath.artifact_path = artifact
    end

    %i[native ruby].each do |engine|
      oracle.each do |decimal, rows|
        context "with engine: #{engine.inspect}, decimal: #{decimal.inspect}" do
          before { require_native! if engine == :native }

          # One example per engine and marker: each example reloads the
          # artifact (spec_helper resets Amath.artifact_path), which is slow.
          it "rejects each oracle row at Parslet's character and byte" do
            expected = rows.to_h { |input, char| [input, [char, input[0, char].bytesize]] }
            actual = rows.keys.to_h do |input|
              Amath.parse(input, decimal: decimal, engine: engine)
              [input, :accepted]
            rescue described_class => e
              [input, [e.char_offset, e.byte_offset]]
            end
            expect(actual).to eq(expected)
          end
        end
      end
    end
  end
end
