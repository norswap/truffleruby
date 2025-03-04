# frozen_string_literal: true

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

# Just to save you 10 seconds, the reason we always use #each to extract
# elements instead of something simpler is because Enumerable can not assume
# any other methods than #each. If needed, class-specific versions of any of
# these methods can be written *in those classes* to override these.

module Enumerable
  def chunk(&original_block)
    initial_state = nil
    raise ArgumentError, 'no block given' unless block_given?
    Enumerator.new do |yielder|
      previous = nil
      accumulate = []
      if initial_state.nil?
        block = original_block
      else
        duplicated_initial_state = initial_state.dup
        block = Proc.new{ |val| original_block.yield(val, duplicated_initial_state)}
      end
      each do |val|
        key = block.yield(val)
        if key.nil? || (key.is_a?(Symbol) && key.to_s[0, 1] == '_')
          yielder.yield [previous, accumulate] unless accumulate.empty?
          accumulate = []
          previous = nil
          case key
          when nil, :_separator
          when :_alone
            yielder.yield [key, [val]]
          else
            raise RuntimeError, 'symbols beginning with an underscore are reserved'
          end
        else
          if previous.nil? || previous == key
            accumulate << val
          else
            yielder.yield [previous, accumulate] unless accumulate.empty?
            accumulate = [val]
          end
          previous = key
        end
      end
      yielder.yield [previous, accumulate] unless accumulate.empty?
    end
  end

  def chunk_while(&block)
    block = Proc.new(block)
    Enumerator.new do |yielder|
      accumulator = nil
      prev = nil
      each do |*elem|
        elem = elem[0] if elem.size == 1
        if accumulator.nil?
          accumulator = [elem]
          prev = elem
        else
          start_new = block.yield(prev, elem)
          if !start_new
            yielder.yield accumulator if accumulator
            accumulator = [elem]
          else
            accumulator << elem
          end
          prev = elem
        end
      end
      yielder.yield accumulator if accumulator
    end
  end

  def collect
    if block_given?
      ary = []
      each do |*o|
        ary << yield(*o)
      end
      ary
    else
      to_enum(:collect) { enumerator_size }
    end
  end

  alias_method :map, :collect

  def count(item = undefined)
    seq = 0
    if !undefined.equal?(item)
      warn 'given block not used', uplevel: 1 if block_given?
      each { |o| seq += 1 if item == o }
    elsif block_given?
      each { |o| seq += 1 if yield(o) }
    else
      each { seq += 1 }
    end
    seq
  end

  def each_entry(*pass)
    return to_enum(:each_entry, *pass) { enumerator_size } unless block_given?
    each(*pass) do |*args|
      yield args.size == 1 ? args[0] : args
    end
    self
  end

  def each_with_object(memo)
    return to_enum(:each_with_object, memo) { enumerator_size } unless block_given?
    each do
      obj = Truffle.single_block_arg
      yield obj, memo
    end
    memo
  end

  def flat_map
    return to_enum(:flat_map) { enumerator_size } unless block_given?

    array = []
    each do |*args|
      result = yield(*args)

      value = Truffle::Type.try_convert(result, Array, :to_ary) || result

      if value.kind_of? Array
        array.concat value
      else
        array.push value
      end
    end

    array
  end

  alias_method :collect_concat, :flat_map

  def lazy
    Enumerator::Lazy.new(self, enumerator_size) do |yielder, *args|
      yielder.<<(*args)
    end
  end

  def enumerator_size
    Truffle::Type.object_respond_to?(self, :size) ? size : nil
  end
  private :enumerator_size

  def group_by
    return to_enum(:group_by) { enumerator_size } unless block_given?

    h = {}
    each do
      o = Truffle.single_block_arg
      key = yield(o)
      if h.key?(key)
        h[key] << o
      else
        h[key] = [o]
      end
    end
    Truffle::Type.infect h, self
    h
  end

  def slice_after(arg = undefined, &block)
    has_arg = !(undefined.equal? arg)
    if block_given?
      raise ArgumentError, 'both pattern and block are given' if has_arg
    else
      raise ArgumentError, 'wrong number of arguments (0 for 1)' unless has_arg
      block = Proc.new{ |elem| arg === elem }
    end
    Enumerator.new do |yielder|
      accumulator = nil
      each do |*elem|
        elem = elem[0] if elem.size == 1
        end_slice = block.yield(elem)
        accumulator ||= []
        if end_slice
          accumulator << elem
          yielder.yield accumulator
          accumulator = nil
        else
          accumulator << elem
        end
      end
      yielder.yield accumulator if accumulator
    end
  end

  def slice_before(arg = undefined, &block)
    if block_given?
      has_init = !(undefined.equal? arg)
      if has_init
        raise ArgumentError, 'both pattern and block are given'
      end
    else
      raise ArgumentError, 'wrong number of arguments (0 for 1)' if undefined.equal? arg
      block = Proc.new{ |elem| arg === elem }
    end
    Enumerator.new do |yielder|
      init = arg.dup if has_init
      accumulator = nil
      each do |*elem|
        elem = elem[0] if elem.size == 1
        start_new = has_init ? block.yield(elem, init) : block.yield(elem)
        if start_new
          yielder.yield accumulator if accumulator
          accumulator = [elem]
        else
          accumulator ||= []
          accumulator << elem
        end
      end
      yielder.yield accumulator if accumulator
    end
  end

  def slice_when(&block)
    block = Proc.new(block)
    Enumerator.new do |yielder|
      accumulator = nil
      prev = nil
      each do |*elem|
        elem = elem[0] if elem.size == 1
        if accumulator.nil?
          accumulator = [elem]
          prev = elem
        else
          start_new = block.yield(prev, elem)
          if start_new
            yielder.yield accumulator if accumulator
            accumulator = [elem]
          else
            accumulator << elem
          end
          prev = elem
        end
      end
      yielder.yield accumulator if accumulator
    end
  end

  def to_a(*arg)
    ary = []
    each(*arg) do
      o = Truffle.single_block_arg
      ary << o
      nil
    end
    Truffle::Type.infect ary, self
    ary
  end
  alias_method :entries, :to_a

  def to_h(*arg)
    h = {}
    each_with_index(*arg) do |elem, i|
      elem = yield(elem) if block_given?
      unless elem.respond_to?(:to_ary)
        raise TypeError, "wrong element type #{elem.class} at #{i} (expected array)"
      end

      ary = elem.to_ary
      if ary.size != 2
        raise ArgumentError, "element has wrong array length (expected 2, was #{ary.size})"
      end

      h[ary[0]] = ary[1]
    end
    h
  end

  def zip(*args)
    args.map! do |a|
      if a.respond_to? :to_ary
        a.to_ary
      else
        a.to_enum(:each)
      end
    end

    results = []
    i = 0
    each do
      o = Truffle.single_block_arg
      entry = args.inject([o]) do |ary, a|
        ary << case a
               when Array
                 a[i]
               else
                 begin
                   a.next
                 rescue StopIteration
                   nil
                 end
               end
      end

      yield entry if block_given?

      results << entry
      i += 1
    end

    return nil if block_given?
    results
  end

  def each_with_index(*args, &block)
    return to_enum(:each_with_index, *args) { enumerator_size } unless block_given?

    if Array === self
      TrufflePrimitive.array_each_with_index(self, block)
    else
      idx = 0
      each(*args) do
        o = Truffle.single_block_arg
        yield o, idx
        idx += 1
      end

      self
    end
  end

  def grep(pattern, &block)
    ary = []

    if block_given?
      each do
        o = Truffle.single_block_arg
        matches = pattern === o
        Truffle::RegexpOperations.set_last_match($~, block.binding)
        if matches
          ary << yield(o)
        end
      end
    else
      each do
        o = Truffle.single_block_arg
        if pattern === o
          ary << o
        end
      end

      Truffle::RegexpOperations.set_last_match($~, TrufflePrimitive.caller_binding)
    end

    ary
  end

  def grep_v(pattern, &block)
    ary = []

    if block_given?
      each do
        o = Truffle.single_block_arg
        matches = pattern === o
        Truffle::RegexpOperations.set_last_match($~, block.binding)
        unless matches
          ary << yield(o)
        end
      end
    else
      each do
        o = Truffle.single_block_arg
        unless pattern === o
          ary << o
        end
      end

      Truffle::RegexpOperations.set_last_match($~, TrufflePrimitive.caller_binding)
    end

    ary
  end

  def sort(&prc)
    ary = to_a
    ary.frozen? ? ary.sort(&prc) : ary.sort!(&prc)
  end

  class SortedElement
    def initialize(val, sort_id)
      @value, @sort_id = val, sort_id
    end

    attr_reader :value
    attr_reader :sort_id

    def <=>(other)
      @sort_id <=> other.sort_id
    end
  end

  def sort_by
    return to_enum(:sort_by) { enumerator_size } unless block_given?

    # Transform each value to a tuple with the value and it's sort by value
    case self
    when Array
      sort_values = map do |x|
        SortedElement.new(x, yield(x))
      end
    else
      sort_values = []
      each do |*x|
        x = x[0] if x.size == 1
        sort_values << SortedElement.new(x, yield(x))
      end
    end

    # Now sort the tuple according to the sort by value
    sort_values.sort!

    # Now strip of the tuple leaving the original value
    sort_values.map! { |ary| ary.value }
  end

  def inject(initial=undefined, sym=undefined, &block)
    if Array === self
      return TrufflePrimitive.array_inject(self, initial, sym, block)
    end

    if !block_given? or !undefined.equal?(sym)
      if undefined.equal?(sym)
        sym = initial
        initial = undefined
      end

      # Do the sym version

      sym = sym.to_sym

      each do
        o = Truffle.single_block_arg
        if undefined.equal? initial
          initial = o
        else
          initial = initial.__send__(sym, o)
        end
      end

      # Block version
    else
      each do
        o = Truffle.single_block_arg
        if undefined.equal? initial
          initial = o
        else
          initial = yield(initial, o)
        end
      end
    end

    undefined.equal?(initial) ? nil : initial
  end
  alias_method :reduce, :inject

  def all?(pattern = undefined)
    if !undefined.equal?(pattern)
      each { return false unless pattern === Truffle.single_block_arg }
    elsif block_given?
      each { |*e| return false unless yield(*e) }
    else
      each { return false unless Truffle.single_block_arg }
    end
    true
  end

  def any?(pattern = undefined)
    if !undefined.equal?(pattern)
      each { return true if pattern === Truffle.single_block_arg }
    elsif block_given?
      each { |*o| return true if yield(*o) }
    else
      each { return true if Truffle.single_block_arg }
    end
    false
  end

  def cycle(many=nil)
    unless block_given?
      return to_enum(:cycle, many) do
        Truffle::EnumerableHelper.cycle_size(enumerator_size, many)
      end
    end

    if many
      many = Truffle::Type.coerce_to_collection_index many
      return nil if many <= 0
    else
      many = nil
    end

    cache = []
    each do
      elem = Truffle.single_block_arg
      cache << elem
      yield elem
    end

    return nil if cache.empty?

    if many
      i = 0
      many -= 1
      while i < many
        cache.each { |o| yield o }
        i += 1
      end
    else
      while true # rubocop:disable Lint/LiteralAsCondition
        cache.each { |o| yield o }
      end
    end

    nil
  end

  def drop(n)
    n = Truffle::Type.coerce_to_collection_index n
    raise ArgumentError, 'attempt to drop negative size' if n < 0

    ary = to_a
    return [] if n > ary.size
    ary[n...ary.size]
  end

  def drop_while
    return to_enum(:drop_while) unless block_given?

    ary = []
    dropping = true
    each do
      obj = Truffle.single_block_arg
      ary << obj unless dropping &&= yield(obj)
    end

    ary
  end

  def each_cons(num)
    n = Truffle::Type.coerce_to_collection_index num
    raise ArgumentError, "invalid size: #{n}" if n <= 0

    unless block_given?
      return to_enum(:each_cons, num) do
        enum_size = enumerator_size
        if enum_size.nil?
          nil
        elsif enum_size == 0 || enum_size < n
          0
        else
          enum_size - n + 1
        end
      end
    end

    array = []
    each do
      element = Truffle.single_block_arg
      array << element
      array.shift if array.size > n
      yield array.dup if array.size == n
    end
    nil
  end

  def each_slice(slice_size)
    n = Truffle::Type.coerce_to_collection_index slice_size
    raise ArgumentError, "invalid slice size: #{n}" if n <= 0

    unless block_given?
      return to_enum(:each_slice, slice_size) do
        enum_size = enumerator_size
        enum_size.nil? ? nil : (enum_size.to_f / n).ceil
      end
    end

    a = []
    each do
      element = Truffle.single_block_arg
      a << element
      if a.length == n
        yield a
        a = []
      end
    end

    yield a unless a.empty?
    nil
  end

  def find(ifnone=nil)
    return to_enum(:find, ifnone) unless block_given?

    each do
      o = Truffle.single_block_arg
      return o if yield(o)
    end

    ifnone.call if ifnone
  end

  alias_method :detect, :find

  def find_all
    return to_enum(:find_all) { enumerator_size } unless block_given?

    ary = []
    each do
      o = Truffle.single_block_arg
      ary << o if yield(o)
    end
    ary
  end

  alias_method :select, :find_all
  alias_method :filter, :find_all

  def find_index(value=undefined)
    if undefined.equal? value
      return to_enum(:find_index) unless block_given?

      i = 0
      each do |*args|
        return i if yield(*args)
        i += 1
      end
    else
      warn 'given block not used', uplevel: 1 if block_given?

      i = 0
      each do
        e = Truffle.single_block_arg
        return i if e == value
        i += 1
      end
    end
    nil
  end

  def first(n=undefined)
    return __take__(n) unless undefined.equal?(n)
    each { |obj| return obj }
    nil
  end

  def min(n = undefined, &block)
    return min_n(n, &block) if !undefined.equal?(n) && !n.nil?
    min_max(-1, &block)
  end

  def min_n(n, &block)
    raise ArgumentError, "negative size #{n}" if n < 0
    return [] if n == 0

    self.sort(&block).first(n)
  end
  private :min_n

  def max(n = undefined, &block)
    return max_n(n, &block) if !undefined.equal?(n) && !n.nil?
    min_max(+1, &block)
  end

  def max_n(n, &block)
    raise ArgumentError, "negative size #{n}" if n < 0
    return [] if n == 0

    self.sort(&block).last(n).reverse
  end
  private :max_n

  def min_max(relative)
    chosen = undefined
    each do
      o = Truffle.single_block_arg
      if undefined.equal? chosen
        chosen = o
      else
        comp = block_given? ? yield(o, chosen) : o <=> chosen
        unless comp
          raise ArgumentError, "comparison of #{o.class} with #{chosen} failed"
        end

        if (Comparable.compare_int(comp) <=> 0) == relative
          chosen = o
        end
      end
    end

    undefined.equal?(chosen) ? nil : chosen
  end
  private :min_max

  private def max_by_n(n, &block)
    n = Truffle::Type.rb_num2long(n)
    raise ArgumentError, "negative size #{n}" if n < 0
    return [] if n == 0
    self.sort_by(&block).last(n).reverse
  end

  def max_by(n = nil, &block)
    return to_enum(:max_by) { enumerator_size } unless block_given?
    return max_by_n(n, &block) unless n.nil?

    max_object = nil
    max_result = undefined

    each do
      object = Truffle.single_block_arg
      result = yield object

      if undefined.equal?(max_result) or \
           Truffle::Type.coerce_to_comparison(max_result, result) < 0
        max_object = object
        max_result = result
      end
    end

    max_object
  end

  private def min_by_n(n, &block)
    n = Truffle::Type.rb_num2long(n)
    raise ArgumentError, "negative size #{n}" if n < 0
    return [] if n == 0
    self.sort_by(&block).first(n)
  end

  def min_by(n = nil, &block)
    return to_enum(:min_by) { enumerator_size } unless block_given?
    return min_by_n(n, &block) unless n.nil?

    min_object = nil
    min_result = undefined

    each do
      object = Truffle.single_block_arg
      result = yield object

      if undefined.equal?(min_result) or \
           Truffle::Type.coerce_to_comparison(min_result, result) > 0
        min_object = object
        min_result = result
      end
    end

    min_object
  end

  def self.sort_proc
    @sort_proc ||= Proc.new do |a, b|
      unless ret = a <=> b
        raise ArgumentError, 'Improper spaceship value'
      end
      ret
    end
  end

  def minmax(&block)
    block = Enumerable.sort_proc unless block
    first_time = true
    min, max = nil

    each do
      object = Truffle.single_block_arg
      if first_time
        min = max = object
        first_time = false
      else
        unless min_cmp = block.call(min, object)
          raise ArgumentError, 'comparison failed'
        end
        min = object if min_cmp > 0

        unless max_cmp = block.call(max, object)
          raise ArgumentError, 'comparison failed'
        end

        max = object if max_cmp < 0
      end
    end
    [min, max]
  end

  def minmax_by(&block)
    return to_enum(:minmax_by) { enumerator_size } unless block_given?

    min_object = nil
    min_result = undefined

    max_object = nil
    max_result = undefined

    each do
      object = Truffle.single_block_arg
      result = yield object

      if undefined.equal?(min_result) or \
           Truffle::Type.coerce_to_comparison(min_result, result) > 0
        min_object = object
        min_result = result
      end

      if undefined.equal?(max_result) or \
           Truffle::Type.coerce_to_comparison(max_result, result) < 0
        max_object = object
        max_result = result
      end
    end

    [min_object, max_object]
  end

  def none?(pattern = undefined)
    if !undefined.equal?(pattern)
      each { return false if pattern === Truffle.single_block_arg }
    elsif block_given?
      each { |*o| return false if yield(*o) }
    else
      each { return false if Truffle.single_block_arg }
    end

    true
  end

  def one?(pattern = undefined)
    found_one = false

    if !undefined.equal?(pattern)
      each do
        if pattern === Truffle.single_block_arg
          return false if found_one
          found_one = true
        end
      end
    elsif block_given?
      each do |*o|
        if yield(*o)
          return false if found_one
          found_one = true
        end
      end
    else
      each do
        if Truffle.single_block_arg
          return false if found_one
          found_one = true
        end
      end
    end

    found_one
  end

  def partition
    return to_enum(:partition) { enumerator_size } unless block_given?

    left = []
    right = []
    each do
      o = Truffle.single_block_arg
      yield(o) ? left.push(o) : right.push(o)
    end

    [left, right]
  end

  def reject
    return to_enum(:reject) { enumerator_size } unless block_given?

    ary = []
    each do
      o = Truffle.single_block_arg
      ary << o unless yield(o)
    end

    ary
  end

  def reverse_each(&block)
    return to_enum(:reverse_each) { enumerator_size } unless block_given?

    # There is no other way then to convert to an array first... see 1.9's source.
    to_a.reverse_each(&block)
    self
  end

  def take(n)
    n = Truffle::Type.coerce_to_collection_index n
    raise ArgumentError, "attempt to take negative size: #{n}" if n < 0

    array = []

    unless n <= 0
      each do
        elem = Truffle.single_block_arg
        array << elem
        break if array.size >= n
      end
    end

    array
  end
  alias_method :__take__, :take
  private :__take__

  def take_while
    return to_enum(:take_while) unless block_given?

    array = []
    each do |elem|
      return array unless yield(elem)
      array << elem
    end

    array
  end

  def include?(obj)
    each { return true if Truffle.single_block_arg == obj }
    false
  end
  alias_method :member?, :include?

  def uniq(&block)
    result = []
    if block_given?
      h = {}
      each do |e|
        v = yield(e)
        unless h.key?(v)
          h[v] = true
          result << e
        end
      end
    else
      h = {}
      each do |e|
        unless h.key?(e)
          h[e] = true
          result << e
        end
      end
    end

    result
  end

  def sum(init = 0)
    if block_given?
      inject(init) { |sum, e| sum + yield(e) }
    else
      inject(init, :+)
    end
  end

end

class Array
  # Copy methods from Enumerable that should also be defined on Array
  alias_method :any?, :any?
  alias_method :take, :take
  alias_method :drop_while, :drop_while
  alias_method :take_while, :take_while
  alias_method :frozen?, :frozen?
  alias_method :sum, :sum
  alias_method :min, :min
  alias_method :max, :max
end
