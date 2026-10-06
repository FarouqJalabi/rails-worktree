module RailsWorktree
  # Writes a marked block into a text file. Repeated writes replace the block in
  # place and leave the rest of the file untouched.
  class ManagedBlock
    def self.write(path, body, start:, finish:)
      new(path, start: start, finish: finish).write(body)
    end

    def initialize(path, start:, finish:)
      @path = path
      @start = start
      @finish = finish
    end

    def write(body)
      block = "#{@start}\n#{body.chomp}\n#{@finish}\n"
      content = File.file?(@path) ? File.read(@path) : ""
      updated =
        if content.include?(@start) && content.include?(@finish)
          content.sub(/#{Regexp.escape(@start)}\n.*?#{Regexp.escape(@finish)}\n?/m) { block }
        elsif content.empty?
          block
        else
          content + (content.end_with?("\n") ? "\n" : "\n\n") + block
        end
      return false if updated == content

      File.write(@path, updated)
      true
    end
  end
end
