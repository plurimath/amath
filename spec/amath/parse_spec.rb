# frozen_string_literal: true

RSpec.describe Amath do
  it "has a version number" do
    expect(Amath::VERSION).to eq("0.2.0")
  end

  it "does not load Plurimath" do
    expect(defined?(Plurimath)).to be_nil
  end

  %i[native ruby].each do |engine|
    context "with engine: #{engine.inspect}" do
      before { require_native! if engine == :native }

      it "parses input into a Parsanol tree" do
        tree = Amath::Parser.raw("x_y", engine: engine)
        expect(tree).to be_a(Hash)
        expect(tree[:expr][:sequence][:symbol]).to be_a(Parsanol::Slice)
        expect(tree[:expr][:sequence][:symbol].to_s).to eq("x")
        expect(tree[:expr][:expr][:expr][:sequence][:symbol].offset).to eq(2)
        expect(described_class.last_engine).to eq(engine)
      end

      it "returns a plain empty String for empty input" do
        tree = Amath::Parser.raw("", engine: engine)
        expect(tree).to eq("")
        expect(tree).to be_an_instance_of(String)
      end

      it "reports leaf offsets in bytes" do
        tree = Amath::Parser.raw("text(é) x", engine: engine)
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
          tree = Amath::Parser.raw(input, decimal: marker, engine: engine)
          expect(tree[:expr][:sequence][:number].to_s).to eq(input)
        end
      end

      it "rejects a number whose marker does not match decimal:" do
        expect { Amath::Parser.raw("1,5", decimal: ".", engine: engine) }
          .to raise_error(Amath::ParseError)
      end

      it "raises ParseError with byte and character positions" do
        expect { Amath::Parser.raw("text(é) 1,", decimal: ",", engine: engine) }
          .to raise_error(Amath::ParseError) { |e|
            expect(e.byte_offset).to eq(10)
            expect(e.char_offset).to eq(9)
            expect(e.input).to eq("text(é) 1,")
            expect(e.message).to include("character 9 (byte 10)")
            expect(e.cause).to be_a(Parsanol::ParseFailed)
          }
        expect(described_class.last_engine).to eq(engine)
      end

      it "rejects invalid trailing text instead of returning a prefix" do
        expect { Amath::Parser.raw("x é", engine: engine) }
          .to raise_error(Amath::ParseError) { |e| expect(e.byte_offset).to eq(2) }
      end
    end
  end

  describe "argument checks" do
    it "rejects an unknown decimal marker" do
      expect { Amath::Parser.raw("1;5", decimal: ";") }
        .to raise_error(ArgumentError, /unsupported decimal marker ";"/)
    end

    it "rejects an unknown engine" do
      expect { Amath::Parser.raw("x", engine: :fast) }
        .to raise_error(ArgumentError, /unknown engine :fast/)
    end

    it "rejects non-String input" do
      expect { Amath::Parser.raw(nil) }.to raise_error(ArgumentError, /must be a String/)
    end

    it "rejects invalid UTF-8" do
      expect { Amath::Parser.raw("x\xFF".b.force_encoding("UTF-8")) }
        .to raise_error(ArgumentError, /not valid UTF-8/)
    end
  end

  # The released 0.1 contract: plurimath 0.11.x calls Amath.parse(text,
  # decimal:) through "~> 0.1" and walks the raw tree. The typed model is a
  # separate entry point, so the return type never depends on the options.
  describe ".parse (amath 0.1 contract)" do
    # The production grammar: these inputs are outside the spike fixture.
    before { described_class.artifact_path = described_class::DEFAULT_ARTIFACT_PATH }

    %i[native ruby].each do |engine|
      it "returns the raw tree on engine: #{engine.inspect}" do
        require_native! if engine == :native
        %w[x_y sqrt(x) 1,5].each do |input|
          decimal = input.include?(",") ? "," : "."
          tree = described_class.parse(input, decimal: decimal, engine: engine)
          expect(tree).to eq(Amath::Parser.raw(input, decimal: decimal, engine: engine))
        end
        expect(described_class.parse("", engine: engine)).to eq("")
      end
    end

    it "keeps amath 0.1's keywords, so dialect: is not one of them" do
      expect { described_class.parse("x", dialect: :legacy) }
        .to raise_error(ArgumentError, /unknown keyword: :dialect/)
    end

    it "keeps amath 0.1's Parser.parse" do
      expect(Amath::Parser.parse("x_y", decimal: ".", engine: :ruby))
        .to eq(Amath::Parser.raw("x_y", engine: :ruby))
    end

    it "leaves the typed model to .parse_model" do
      expect(described_class.parse_model("x_y")).to be_a(Amath::Model::Document)
      expect(described_class.parse_model("ustd(1.2, 0.1)", dialect: :pma)).to be_a(Amath::Model::PmaDocument)
    end
  end
end
