# frozen_string_literal: true

# Copyright (c) 2016, 2019 Oracle and/or its affiliates. All rights reserved. This
# code is released under a tri EPL/GPL/LGPL license. You can use it,
# redistribute it and/or modify it under the terms of the:
#
# Eclipse Public License version 2.0, or
# GNU General Public License version 2, or
# GNU Lesser General Public License version 2.1.

# Copyright (c) 2007-2015, Evan Phoenix and contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of Rubinius nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

class Exception
  def ==(other)
    other.instance_of?(Truffle::Type.object_class(self)) &&
      message == other.message &&
      backtrace == other.backtrace
  end

  def message
    self.to_s
  end

  def to_s
    msg = TrufflePrimitive.exception_message self
    if msg.nil?
      formatter = TrufflePrimitive.exception_formatter self
      if formatter.nil?
        self.class.to_s
      else
        msg = formatter.call(self).to_s
        TrufflePrimitive.exception_set_message self, msg
        msg
      end
    else
      msg.to_s
    end
  end

  # This is here rather than in yaml.rb because it contains "private"
  # information, ie, the list of ivars. Putting it over in the yaml
  # source means it's easy to forget about.
  def to_yaml_properties
    list = super
    list.delete :@backtrace
    list.delete :@custom_backtrace
    list
  end

  # Needed to properly implement #exception, which must clone and call
  # #initialize again, BUT not a subclasses initialize.
  alias_method :__initialize__, :initialize

  def backtrace?
    result = TrufflePrimitive.exception_backtrace? self
    if !undefined.equal?(result)
      result
    else
      backtrace ? true : false
    end
  end

  def set_backtrace(bt)
    case bt
    when Array
      if bt.all? { |s| s.kind_of? String }
        @custom_backtrace = bt
      else
        raise TypeError, 'backtrace must be Array of String'
      end
    when String
      @custom_backtrace = [bt]
    when nil
      @custom_backtrace = nil
    else
      raise TypeError, 'backtrace must be Array of String'
    end
  end

  def set_context(ctx)
    if ctx.kind_of? Exception
      @parent = ctx
    else
      set_backtrace(ctx)
    end
  end

  def inspect
    s = self.to_s
    if s.empty?
      self.class.name
    else
      "#<#{self.class.name}: #{s}>"
    end
  end

  def full_message(highlight: undefined, order: :bottom)
    bt = backtrace || caller(1..1)
    "#{bt[0]}: #{Truffle::ExceptionOperations.message_and_class(self)}\n" + bt[1..-1].map do |l|
      "\tfrom #{l}\n"
    end.join
  end

  class << self
    alias_method :exception, :new
  end

  def exception(message=nil)
    if message
      unless message.equal? self
        # As strange as this might seem, this IS actually the protocol
        # that MRI implements for this. The explicit call to
        # Exception#initialize (via __initialize__) is exactly what MRI
        # does.
        e = clone
        Truffle.privately do
          e.__initialize__(message)
        end
        return e
      end
    end

    self
  end

  def location
    [context.file.to_s, context.line]
  end
end

class PrimitiveFailure < Exception
end

class ScriptError < Exception
end

class StandardError < Exception
end

class SignalException < Exception
end

class NoMemoryError < Exception
end

class ZeroDivisionError < StandardError
end

class ArgumentError < StandardError
  def to_s
    if @given and @expected
      if @method_name
        "method '#{@method_name}': given #{@given}, expected #{@expected}"
      else
        "given #{@given}, expected #{@expected}"
      end
    else
      super
    end
  end
end

class UncaughtThrowError < ArgumentError
  attr_reader :tag
  attr_reader :value

  def initialize(tag, value, *rest)
    @tag = tag
    @value = value
    super(*rest)
  end

  def to_s
    sprintf(TrufflePrimitive.exception_message(self), @tag)
  end
end

class IndexError < StandardError
end

class StopIteration < IndexError
end

class RangeError < StandardError
end

class FloatDomainError < RangeError
end

class LocalJumpError < StandardError
end

class NameError < StandardError

  def initialize(*args)
    name = args.size > 1 ? args.pop : nil
    super(*args)
    TrufflePrimitive.name_error_set_name self, name
  end
end

class NoMethodError < NameError

  def initialize(*arguments)
    args = arguments.size > 2 ? arguments.pop : nil
    super(*arguments) # TODO BJF Jul 24, 2016 Need to handle NoMethodError.new(1,2,3,4)
    TrufflePrimitive.no_method_error_set_args self, args
  end
end

class RuntimeError < StandardError
end

class SecurityError < Exception
end

class ThreadError < StandardError
end

class FiberError < StandardError
end

class TypeError < StandardError
end

class FloatDomainError < RangeError
end

class RegexpError < StandardError
end

class LoadError < ScriptError
  attr_accessor :path

  class InvalidExtensionError < LoadError
  end

  class MRIExtensionError < InvalidExtensionError
  end
end

class NotImplementedError < ScriptError
end

class Interrupt < SignalException
  def initialize(message = nil)
    super(Signal.list['INT'], message)
  end
end

class IOError < StandardError
end

class EOFError < IOError
end

class LocalJumpError < StandardError
end

class SyntaxError < ScriptError
  attr_accessor :column
  attr_accessor :line
  attr_accessor :file
  attr_accessor :code

  def reason
    @reason_message
  end
end

class SystemExit < Exception

  ##
  # Process exit status if this exception is raised

  attr_reader :status

  ##
  # Creates a SystemExit exception with optional status and message.  If the
  # status is omitted, Process::EXIT_SUCCESS is used.
  #--
  # *args is used to simulate optional prepended argument like MRI

  def initialize(first=nil, *args)
    if first.kind_of?(Integer)
      status = first
      super(*args)
    else
      status = Process::EXIT_SUCCESS
      super
    end

    @status = status
  end

  ##
  # Returns true is exiting successfully, false if not. A successful exit is
  # one with a status equal to 0 (zero). Any other status is considered a
  # unsuccessful exit.

  def success?
    status == Process::EXIT_SUCCESS
  end

end


class SystemCallError < StandardError

  def self.errno_error(message, errno, location)
    message = message ? " - #{message}" : +''
    message = " @ #{location}#{message}" if location
    TrufflePrimitive.exception_errno_error message, errno
  end

  # We use .new here because when errno is set, we attempt to
  # lookup and return a subclass of SystemCallError, specifically,
  # one of the Errno subclasses.
  def self.new(*args)
    # This method is used 2 completely different ways. One is when it's called
    # on SystemCallError, in which case it tries to construct a Errno subclass
    # or makes a generic instead of itself.
    #
    # Otherwise it's called on a Errno subclass and just helps setup
    # a instance of the subclass
    if self.equal? SystemCallError
      case args.size
      when 1
        if args.first.kind_of?(Integer)
          errno = args.first
          message = nil
        else
          errno = nil
          message = StringValue(args.first)
        end
        location = nil
      when 2
        message, errno = args
        location = nil
      when 3
        message, errno, location = args
      else
        raise ArgumentError, "wrong number of arguments (#{args.size} for 1..3)"
      end

      # If it corresponds to a known Errno class, create and return it now
      if errno && error = SystemCallError.errno_error(message, errno, location)
        return error
      else
        return super(message, errno, location)
      end
    else
      case args.size
      when 0
        message = nil
        location = nil
      when 1
        message = StringValue(args.first)
        location = nil
      when 2
        message, location = args
      else
        raise ArgumentError, "wrong number of arguments (#{args.size} for 0..2)"
      end

      if defined?(self::Errno) && self::Errno.kind_of?(Integer)
        error = SystemCallError.errno_error(message, self::Errno, location)
        if error && error.class.equal?(self)
          return error
        end
      end

      super(*args)
    end
  end

  # Must do this here because we have a unique new and otherwise .exception will
  # call Exception.new because of the alias in Exception.
  class << self
    alias_method :exception, :new
  end

  # Use splat args here so that arity returns -1 to match MRI.
  def initialize(*args)
    message, errno, location = args
    TrufflePrimitive.exception_set_errno self, errno

    msg = +'unknown error'
    msg << " @ #{StringValue(location)}" if location
    msg << " - #{StringValue(message)}" if message
    super(msg)
  end
end

class KeyError < IndexError

  attr_reader :receiver
  attr_reader :key

  def initialize(message = nil, receiver: nil, key: nil)
    @receiver = receiver
    @key = key
    super(message)
  end
end

class SignalException < Exception

  alias :signm :message
  attr_reader :signo

  def initialize(sig, message = undefined)
    signo = Truffle::Type.rb_check_to_integer(sig, :to_int)
    if signo.nil?
      raise ArgumentError, 'wrong number of arguments (given 2, expected 1)' unless undefined.equal?(message)
      if sig.is_a?(Symbol)
        sig = sig.to_s
      else
        sig = StringValue(sig)
      end
      signal_name = sig
      if signal_name.start_with?('SIG')
        signal_name = signal_name[3..-1]
      end
      signo = Signal::Names[signal_name]
      if signo.nil?
        raise ArgumentError, "invalid signal name SIG#{sig}"
      end
      name_with_prefix = 'SIG%s' % signal_name
    else
      if signo < 0 || signo > Signal::NSIG
        raise ArgumentError, "invalid signal number (#{signo})"
      end
      name_with_prefix = if undefined.equal?(message)
                           name = Signal::Numbers[signo]
                           if name.nil?
                             'SIG%d' % signo
                           else
                             'SIG%s' % name
                           end
                         else
                           message
                         end
    end
    @signo = signo
    super(name_with_prefix)
  end

  private def reached_top_level
    if @signo == Signal::Names['VTALRM']
      warn 'not acting on top level SignalException for SIGVTALRM as it is VM reserved'
      return
    end

    begin
      Signal.trap(@signo, 'SYSTEM_DEFAULT')
    rescue ArgumentError
      # some signals are reserved but we can raise them anyways
      nil
    end
    Truffle::POSIX.raise_signal(@signo)
  end

end

class StopIteration
  attr_accessor :result
  private :result=
end
