# frozen_string_literal: true

RSpec.describe Amath do
  it "has a version number" do
    expect(Amath::VERSION).to eq("0.1.0")
  end

  it "does not load Plurimath" do
    expect(defined?(Plurimath)).to be_nil
  end

  %i[native ruby].each do |engine|
    context "with engine: #{engine.inspect}" do
      before { require_native! if engine == :native }

      it "parses input into a Parsanol tree" do
        tree = described_class.parse("x_y", engine: engine)
        expect(tree).to be_a(Hash)
        expect(tree[:expr][:sequence][:symbol]).to be_a(Parsanol::Slice)
        expect(tree[:expr][:sequence][:symbol].to_s).to eq("x")
        expect(tree[:expr][:expr][:expr][:sequence][:symbol].offset).to eq(2)
        expect(described_class.last_engine).to eq(engine)
      end

      it "returns a plain empty String for empty input" do
        tree = described_class.parse("", engine: engine)
        expect(tree).to eq("")
        expect(tree).to be_an_instance_of(String)
      end

      it "reports leaf offsets in bytes" do
        tree = described_class.parse("text(é) x", engine: engine)
        leaf = tree[:expr][:expr][:sequence][:symbol]
        expect(leaf.to_s).to eq("x")
        expect(leaf.offset).to eq(9) # "x" is character 8, byte 9
      end

      {
        "." => "1.5",
        "," => "1,5",
        "٫" => "1٫5",
      }.each do |marker, input|
        it "parses #{input.inspect} with decimal: #{marker.inspect}" do
          tree = described_class.parse(input, decimal: marker, engine: engine)
          expect(tree[:expr][:sequence][:number].to_s).to eq(input)
        end
      end

      it "rejects a number whose marker does not match decimal:" do
        expect { described_class.parse("1,5", decimal: ".", engine: engine) }
          .to raise_error(Amath::ParseError)
      end

      it "raises ParseError with byte and character positions" do
        expect { described_class.parse("text(é) 1,", decimal: ",", engine: engine) }
          .to raise_error(Amath::ParseError) { |e|
            expect(e.byte_offset).to eq(11)
            expect(e.char_offset).to eq(10)
            expect(e.input).to eq("text(é) 1,")
            expect(e.message).to include("character 10 (byte 11)")
            expect(e.cause).to be_a(Parsanol::ParseFailed)
          }
        expect(described_class.last_engine).to eq(engine)
      end

      it "rejects invalid trailing text instead of returning a prefix" do
        expect { described_class.parse("x é", engine: engine) }
          .to raise_error(Amath::ParseError) { |e| expect(e.byte_offset).to eq(2) }
      end
    end
  end

  describe "argument checks" do
    it "rejects an unknown decimal marker" do
      expect { described_class.parse("1;5", decimal: ";") }
        .to raise_error(ArgumentError, /unsupported decimal marker ";"/)
    end

    it "rejects an unknown engine" do
      expect { described_class.parse("x", engine: :fast) }
        .to raise_error(ArgumentError, /unknown engine :fast/)
    end

    it "rejects non-String input" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /must be a String/)
    end

    it "rejects invalid UTF-8" do
      expect { described_class.parse("x\xFF".b.force_encoding("UTF-8")) }
        .to raise_error(ArgumentError, /not valid UTF-8/)
    end
  end
end
