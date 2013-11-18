class Tresor::TCTP::SequenceQueue
  attr_accessor :sequence
  attr_accessor :sequence_mutex
  attr_accessor :sequence_index

  def initialize(sequence_index = 0)
    @sequence = {}
    @sequence_mutex = Mutex.new
    @sequence_index = sequence_index
  end

  def shift_next_items
    sequence_mutex.synchronize do
      next_items = {}

      while true
        next_item = sequence.delete(@sequence_index)

        unless next_item.nil?
          next_items[@sequence_index] = next_item

          @sequence_index += 1
        else
          break
        end
      end

      next_items
    end
  end

  def push(item, number)
    sequence_mutex.synchronize do
      sequence[number] = item
    end
  end
end