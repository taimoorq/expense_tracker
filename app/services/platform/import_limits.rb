module Platform
  module ImportLimits
    class Exceeded < StandardError; end

    CSV_MAX_BYTES = 10.megabytes
    CSV_MAX_ROWS = 25_000
    CSV_MAX_FIELD_SIZE = 64.kilobytes
    CSV_MAX_COLUMNS = 100
    BACKUP_MAX_BYTES = 100.megabytes
    # Encrypted envelopes include base64 and message serialization overhead.
    BACKUP_MAX_WIRE_BYTES = 2 * BACKUP_MAX_BYTES

    def self.read(source, max_bytes:, label:)
      return source.to_s.tap { |value| check_bytes!(value, max_bytes: max_bytes, label: label) } unless source.respond_to?(:read)

      contents = +"".b
      loop do
        chunk = source.read([ 64.kilobytes, max_bytes + 1 - contents.bytesize ].min)
        break if chunk.nil? || chunk.empty?

        contents << chunk
        check_bytes!(contents, max_bytes: max_bytes, label: label)
      end
      check_bytes!(contents, max_bytes: max_bytes, label: label)
      contents
    end

    def self.check_bytes!(contents, max_bytes:, label:)
      return if contents.bytesize <= max_bytes

      raise Exceeded, "#{label} exceeds the #{max_bytes / 1.megabyte} MB size limit."
    end

    def self.read_csv(path)
      File.open(path, "r:bom|utf-8") do |file|
        read(file, max_bytes: CSV_MAX_BYTES, label: "CSV file").force_encoding(Encoding::UTF_8)
      end
    end

    def self.check_csv_row!(values, row_count:)
      raise Exceeded, "CSV exceeds the #{CSV_MAX_ROWS} row limit." if row_count > CSV_MAX_ROWS
      raise Exceeded, "CSV exceeds the #{CSV_MAX_COLUMNS} column limit." if values.size > CSV_MAX_COLUMNS
      if values.any? { |value| value.to_s.bytesize > CSV_MAX_FIELD_SIZE }
        raise Exceeded, "CSV contains a field larger than #{CSV_MAX_FIELD_SIZE / 1.kilobyte} KB."
      end
    end
  end
end
