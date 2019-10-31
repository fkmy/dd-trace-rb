require 'thread'
require 'ddtrace/runtime/object_space'

module Datadog
  # Trace buffer that stores application traces. The buffer has a maximum size and when
  # the buffer is full, a random trace is discarded. This class is thread-safe and is used
  # automatically by the ``Tracer`` instance when a ``Span`` is finished.
  class TraceBuffer
    def initialize(max_size)
      @max_size = max_size

      @mutex = Mutex.new()
      @traces = []
      @closed = false

      # Initialize metric values
      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    end

    # Add a new ``trace`` in the local queue. This method doesn't block the execution
    # even if the buffer is full. In that case, a random trace is discarded.
    def push(trace)
      @mutex.synchronize do
        return if @closed
        len = @traces.length
        if len < @max_size || @max_size <= 0
          @traces << trace
          measure_accept(trace)
        else
          # we should replace a random trace with the new one
          replace_index = rand(len)
          replaced_trace = @traces[replace_index]
          @traces[replace_index] = trace
          measure_drop(replaced_trace, trace)
        end
      end
    end

    # Return the current number of stored traces.
    def length
      @mutex.synchronize do
        return @traces.length
      end
    end

    # Return if the buffer is empty.
    def empty?
      @mutex.synchronize do
        return @traces.empty?
      end
    end

    # Stored traces are returned and the local buffer is reset.
    def pop
      @mutex.synchronize do
        traces = @traces
        @traces = []

        measure_pop(traces)

        return traces
      end
    end

    def close
      @mutex.synchronize do
        @closed = true
      end
    end

    # Aggregate metrics:
    # They reflect buffer activity since last #pop.
    # These may not be as accurate or as granular, but they
    # don't use as much network traffic as live stats.

    def measure_accept(trace)
      @buffer_spans += trace.length
      @buffer_accepted += 1
      @buffer_accepted_lengths += trace.length
    rescue StandardError => e
      Datadog::Tracer.log.debug("Failed to measure queue accept. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_drop(old_trace, new_trace)
      @buffer_dropped += 1
      @buffer_spans -= old_trace.length
      @buffer_accepted_lengths -= old_trace.length
      @buffer_accepted += 1
      @buffer_spans += new_trace.length
      @buffer_accepted_lengths += new_trace.length
    rescue StandardError => e
      Datadog::Tracer.log.debug("Failed to measure queue drop. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_pop(traces)
      # Accepted
      Debug::Health.metrics.queue_accepted(@buffer_accepted)
      Debug::Health.metrics.queue_accepted_lengths(@buffer_accepted_lengths)
      Debug::Health.metrics.queue_accepted_size { measure_traces_size(traces) }

      # Dropped
      Debug::Health.metrics.queue_dropped(@buffer_dropped)

      # Queue gauges
      Debug::Health.metrics.queue_max_length(@max_size)
      Debug::Health.metrics.queue_spans(@buffer_spans)
      Debug::Health.metrics.queue_length(traces.length)
      Debug::Health.metrics.queue_size { measure_traces_size(traces) }

      # Reset aggregated metrics
      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    rescue StandardError => e
      Datadog::Tracer.log.debug("Failed to measure queue. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_traces_size(traces)
      traces.inject(Datadog::Runtime::ObjectSpace.estimate_bytesize(traces)) do |sum, trace|
        sum + measure_trace_size(trace)
      end
    end

    def measure_trace_size(trace)
      trace.inject(Datadog::Runtime::ObjectSpace.estimate_bytesize(trace)) do |sum, span|
        sum + Datadog::Runtime::ObjectSpace.estimate_bytesize(span)
      end
    end
  end
end
