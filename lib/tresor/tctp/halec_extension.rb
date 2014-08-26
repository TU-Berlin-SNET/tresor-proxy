class Rack::TCTP::HALEC
  # Reactor scheduled queue for HALEC operations
  # @!attr [rw] queue
  # @return [EventMachine::Queue] queue The Queue
  attr_accessor :queue

  # TCTP session cookie associated with this HALEC
  attr_accessor :tctp_session_cookie

  def start_queue_popping
    queue_pop_proc = proc { |proc|
      log.debug ("HALEC #{url}") {"Calling proc #{proc.to_s}"}

      proc.call

      queue.pop queue_pop_proc
    }

    queue.pop queue_pop_proc
  end
end