# frozen_string_literal: true

# Copyright (c) 2015, 2019 Oracle and/or its affiliates. All rights reserved. This
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

class Array
  include Enumerable

  # The flow control for many of these methods is
  # pretty evil due to how MRI works. There is
  # also a lot of duplication of code due to very
  # subtle processing differences and, in some
  # cases, to avoid mutual dependency. Apologies.


  def self.[](*args)
    ary = allocate
    ary.replace args
    ary
  end

  # Try to convert obj into an array, using to_ary method.
  # Returns converted array or nil if obj cannot be converted
  # for any reason. This method is to check if an argument is an array.
  def self.try_convert(obj)
    Truffle::Type.try_convert obj, Array, :to_ary
  end

  def &(other)
    other = Truffle::Type.coerce_to other, Array, :to_ary

    h = {}
    other.each { |e| h[e] = true }
    select { |x| h.delete x }
  end

  def |(other)
    other = Truffle::Type.coerce_to other, Array, :to_ary

    h = {}
    each { |e| h[e] = true }
    other.each { |e| h[e] = true }
    h.keys
  end

  def -(other)
    other = Truffle::Type.coerce_to other, Array, :to_ary

    h = {}
    other.each { |e| h[e] = true }
    reject { |x| h.include? x }
  end

  def <=>(other)
    other = Truffle::Type.rb_check_convert_type other, Array, :to_ary
    return 0 if equal? other
    return nil if other.nil?

    total = other.size

    Thread.detect_recursion self, other do
      i = 0
      count = total < size ? total : size

      while i < count
        order = self[i] <=> other[i]
        return order unless order == 0

        i += 1
      end
    end

    # subtle: if we are recursing on that pair, then let's
    # no go any further down into that pair;
    # any difference will be found elsewhere if need be
    size <=> total
  end

  def *(count)
    result = TrufflePrimitive.array_mul(self, count)
    if !undefined.equal?(result)
      result
    elsif str = Truffle::Type.rb_check_convert_type(count, String, :to_str)
      join(str)
    else
      self * Truffle::Type.coerce_to(count, Integer, :to_int)
    end
  end

  def ==(other)
    result = TrufflePrimitive.array_equal self, other
    unless undefined.equal?(result)
      return result
    end

    return true if equal?(other)
    unless other.kind_of? Array
      return false unless other.respond_to? :to_ary
      return other == self
    end

    return false unless size == other.size

    Thread.detect_recursion self, other do
      i = 0
      total = size

      while i < total
        return false unless TrufflePrimitive.object_same_or_equal(self[i], other[i])
        i += 1
      end
    end

    true
  end

  private def element_reference_fallback(start, length)
    if undefined.equal?(length)
      arg = start
      case arg
      when Range
        unless arg.begin.respond_to?(:to_int)
          raise TypeError, "no implicit conversion of #{arg.begin.class} into Integer"
        end
        unless arg.end.respond_to?(:to_int)
          raise TypeError, "no implicit conversion of #{arg.end.class} into Integer"
        end
        start_index = arg.begin.to_int
        end_index = arg.end.to_int
        Truffle::Type.check_long(start_index)
        Truffle::Type.check_long(end_index)
        start_index = Truffle::Type.clamp_to_int(start_index)
        end_index = Truffle::Type.clamp_to_int(end_index)
        range = Range.new(start_index, end_index, arg.exclude_end?)
        TrufflePrimitive.array_aref(self, range, undefined)
      else
        arg = Truffle::Type.rb_num2long(arg)
        return nil unless Truffle::Type.fits_into_int?(arg)
        TrufflePrimitive.array_aref(self, arg, undefined)
      end
    else
      start_index = start.to_int
      end_index = length.to_int
      Truffle::Type.check_long(start_index)
      Truffle::Type.check_long(end_index)
      start_index = Truffle::Type.clamp_to_int(start_index)
      end_index = Truffle::Type.clamp_to_int(end_index)
      TrufflePrimitive.array_aref(self, start_index, end_index)
    end
  end

  private def element_set_fallback(index, length, value)
    if undefined.equal?(value)
      value = length
      if Range === index
        index = TrufflePrimitive.range_to_int_range(index)
        converted = Array.try_convert(value)
        converted = [value] unless converted
        TrufflePrimitive.array_aset(self, index, converted, undefined)
        value
      else
        index = Truffle::Type.rb_num2long(index)
        TrufflePrimitive.array_aset(self, index, value, undefined)
      end
    else
      index = Truffle::Type.rb_num2long(index)
      length = Truffle::Type.rb_num2long(length)
      converted = value
      unless Array === value
        converted = Array.try_convert(value)
        converted = [value] unless converted
      end
      TrufflePrimitive.array_aset(self, index, length, converted)
      value
    end
  end

  def assoc(obj)
    each do |x|
      if x.kind_of? Array and x.first == obj
        return x
      end
    end

    nil
  end

  def bsearch(&block)
    return to_enum :bsearch unless block_given?

    if idx = bsearch_index(&block)
      self[idx]
    else
      nil
    end
  end

  def bsearch_index
    return to_enum :bsearch_index unless block_given?

    min = 0
    max = total = size

    last_true = nil
    i = size / 2

    while max >= min and i >= 0 and i < total
      x = yield at(i)

      return i if x == 0

      case x
      when Numeric
        if x > 0
          min = i + 1
        else
          max = i - 1
        end
      when true
        last_true = i
        max = i - 1
      when false, nil
        min = i + 1
      else
        raise TypeError, 'wrong argument type (must be numeric, true, false or nil)'
      end

      i = min + (max - min) / 2
    end

    return i if max > min
    return last_true if last_true

    nil
  end

  def combination(num)
    num = Truffle::Type.coerce_to_collection_index num

    unless block_given?
      return to_enum(:combination, num) do
        combination_size(num)
      end
    end

    if num == 0
      yield []
    elsif num == 1
      each do |i|
        yield [i]
      end
    elsif num == size
      yield self.dup
    elsif num >= 0 && num < size
      stack = Array.new(num + 1, 0)
      chosen = Array.new(num)
      lev = 0
      done = false
      stack[0] = -1
      until done
        chosen[lev] = self.at(stack[lev+1])
        while lev < num - 1
          lev += 1
          chosen[lev] = self.at(stack[lev+1] = stack[lev] + 1)
        end
        yield chosen.dup
        lev += 1
        begin
          done = lev == 0
          stack[lev] += 1
          lev -= 1
        end while stack[lev+1] + num == size + lev + 1
      end
    end
    self
  end

  def count(item = undefined)
    seq = 0
    if !undefined.equal?(item)
      each { |o| seq += 1 if item == o }
    elsif block_given?
      each { |o| seq += 1 if yield(o) }
    else
      return size
    end
    seq
  end

  def cycle(n = nil)
    unless block_given?
      return to_enum(:cycle, n) do
        Truffle::EnumerableHelper.cycle_size(size, n)
      end
    end

    return nil if empty?

    if nil.equal? n
      until empty?
        each { |x| yield x }
      end
    else
      n = Truffle::Type.coerce_to_collection_index n
      n.times do
        each { |x| yield x }
      end
    end
    nil
  end

  def delete_if(&block)
    return to_enum(:delete_if) { size } unless block_given?
    reject!(&block)
    self
  end

  def difference(*others)
    other = []
    others.each { |a| other = other | a }
    self - other
  end

  def dig(idx, *more)
    result = self.at(idx)
    if result.nil? || more.empty?
      result
    else
      raise TypeError, "#{result.class} does not have #dig method" unless result.respond_to?(:dig)
      result.dig(*more)
    end
  end

  def each_index
    return to_enum(:each_index) { size } unless block_given?

    i = 0
    total = size

    while i < total
      yield i
      i += 1
    end

    self
  end

  def eql?(other)
    result = TrufflePrimitive.array_eql self, other
    unless undefined.equal?(result)
      return result
    end

    return true if equal? other
    return false unless other.kind_of?(Array)
    return false if size != other.size

    Thread.detect_recursion self, other do
      i = 0
      each do |x|
        return false unless x.eql? other[i]
        i += 1
      end
    end

    true
  end

  def empty?
    size == 0
  end

  def fetch(idx, default=undefined)
    orig = idx
    idx = Truffle::Type.coerce_to_collection_index idx

    idx += size if idx < 0

    if idx < 0 or idx >= size
      if block_given?
        warn 'block supersedes default value argument', uplevel: 1 unless undefined.equal?(default)

        return yield(orig)
      end

      return default unless undefined.equal?(default)

      raise IndexError, "index #{idx} out of bounds"
    end

    at(idx)
  end

  private def fill_internal(a=undefined, b=undefined, c=undefined)
    Truffle.check_frozen

    if block_given?
      unless undefined.equal?(c)
        raise ArgumentError, 'wrong number of arguments'
      end
      one = a
      two = b
    else
      if undefined.equal?(a)
        raise ArgumentError, 'wrong number of arguments'
      end
      obj = a
      one = b
      two = c
    end

    if undefined.equal?(one) || !one
      left = 0
      right = size
    elsif one.kind_of? Range
      raise TypeError, 'length invalid with range' unless undefined.equal?(two)

      left = Truffle::Type.coerce_to_collection_length one.begin
      left += size if left < 0
      raise RangeError, "#{one.inspect} out of range" if left < 0

      right = Truffle::Type.coerce_to_collection_length one.end
      right += size if right < 0
      right += 1 unless one.exclude_end?
      return self if right <= left           # Nothing to modify

    elsif one
      left = Truffle::Type.coerce_to_collection_length one
      left += size if left < 0
      left = 0 if left < 0

      if !undefined.equal?(two) and two
        begin
          right = Truffle::Type.coerce_to_collection_length two
        rescue ArgumentError
          raise RangeError, 'bignum too big to convert into `long'
        rescue TypeError
          raise ArgumentError, 'second argument must be an Integer'
        end

        return self if right == 0
        right += left
      else
        right = size
      end
    end

    unless Truffle::Type.fits_into_long?(left) && Truffle::Type.fits_into_long?(right)
      raise ArgumentError, 'argument too big'
    end

    i = left
    if block_given?
      while i < right
        self[i] = yield(i)
        i += 1
      end
    else
      while i < right
        self[i] = obj
        i += 1
      end
    end

    self
  end

  def first(n = undefined)
    return at(0) if undefined.equal?(n)

    n = Truffle::Type.coerce_to_collection_index(n)
    raise ArgumentError, 'Size must be positive' if n < 0

    Array.new self[0, n]
  end

  def flatten(level=-1)
    level = Truffle::Type.coerce_to_collection_index level
    return self.dup if level == 0

    out = self.class.allocate # new_reserved size
    recursively_flatten(self, out, level)
    Truffle::Type.infect(out, self)
    out
  end

  def flatten!(level=-1)
    Truffle.check_frozen

    level = Truffle::Type.coerce_to_collection_index level
    return nil if level == 0

    out = self.class.allocate # new_reserved size
    if recursively_flatten(self, out, level)
      TrufflePrimitive.steal_array_storage(self, out)
      return self
    end

    nil
  end

  def hash
    unless TrufflePrimitive.object_can_contain_object(self)
      # Primitive arrays do not need the recursion check
      return hash_internal
    end

    hash_val = size

    # This is duplicated and manually inlined code from Thread for performance
    # reasons. Before refactoring it, please benchmark it and compare your
    # refactoring against the original.

    id = object_id
    objects = Thread.current.recursive_objects

    # If there is already an our version running...
    if objects.key? :__detect_outermost_recursion__

      # If we've seen self, unwind back to the outer version
      if objects.key? id
        raise Thread::InnerRecursionDetected
      end

      # .. or compute the hash value like normal
      begin
        objects[id] = true

        hash_val = hash_internal
      ensure
        objects.delete id
      end

      return hash_val
    else
      # Otherwise, we're the outermost version of this code..
      begin
        objects[:__detect_outermost_recursion__] = true
        objects[id] = true

        hash_val = hash_internal

        # An inner version will raise to return back here, indicating that
        # the whole structure is recursive. In which case, abandon most of
        # the work and return a simple hash value.
      rescue Thread::InnerRecursionDetected
        return size
      ensure
        objects.delete :__detect_outermost_recursion__
        objects.delete id
      end
    end

    hash_val
  end
  Truffle::Graal.always_split instance_method(:hash)

  def find_index(obj=undefined)
    super
  end
  alias_method :index, :find_index

  def insert(idx, *items)
    Truffle.check_frozen

    return self if items.length == 0

    # Adjust the index for correct insertion
    idx = Truffle::Type.coerce_to_collection_index idx
    idx += (size + 1) if idx < 0    # Negatives add AFTER the element
    raise IndexError, "#{idx} out of bounds" if idx < 0

    self[idx, 0] = items   # Cheat
    self
  end
  Truffle::Graal.always_split instance_method(:insert)

  def inspect
    return '[]'.encode(Encoding::US_ASCII) if size == 0
    comma = ', '
    result = +'['

    return +'[...]' if Thread.detect_recursion self do
      each_with_index do |element, index|
        temp = Truffle::Type.rb_inspect(element)
        result.force_encoding(temp.encoding) if index == 0
        result << temp << comma
      end
    end

    Truffle::Type.infect(result, self)
    result.shorten!(2)
    result << ']'
    result
  end
  alias_method :to_s, :inspect

  def join(sep=nil)
    return ''.encode(Encoding::US_ASCII) if size == 0

    out = +''
    raise ArgumentError, 'recursive array join' if Thread.detect_recursion self do
      sep = sep.nil? ? $, : StringValue(sep)

      # We've manually unwound the first loop entry for performance
      # reasons.
      x = self[0]

      if str = String.try_convert(x)
        x = str
      elsif ary = Array.try_convert(x)
        x = ary.join(sep)
      else
        x = x.to_s
      end

      out.force_encoding(x.encoding)
      out << x

      total = size()
      i = 1

      while i < total
        out << sep if sep

        x = self[i]

        if str = String.try_convert(x)
          x = str
        elsif ary = Array.try_convert(x)
          x = ary.join(sep)
        else
          x = x.to_s
        end

        out << x
        i += 1
      end
    end

    Truffle::Type.infect(out, self)
  end

  def keep_if(&block)
    return to_enum(:keep_if) { size } unless block_given?

    Truffle.check_frozen

    TrufflePrimitive.steal_array_storage(self, select(&block))
  end

  def last(n=undefined)
    if undefined.equal?(n)
      return at(-1)
    elsif size < 1
      return []
    end

    n = Truffle::Type.coerce_to_collection_index n
    return [] if n == 0

    raise ArgumentError, 'count must be positive' if n < 0

    n = size if n > size
    Array.new self[-n..-1]
  end

  def permutation(num=undefined, &block)
    unless block_given?
      return to_enum(:permutation, num) do
        permutation_size(num)
      end
    end

    if undefined.equal? num
      num = size
    else
      num = Truffle::Type.coerce_to_collection_index num
    end

    if num < 0 || size < num
      # no permutations, yield nothing
    elsif num == 0
      # exactly one permutation: the zero-length array
      yield []
    elsif num == 1
      # this is a special, easy case
      each { |val| yield [val] }
    else
      # this is the general case
      perm = Array.new(num)
      used = Array.new(size, false)

      if block
        # offensive (both definitions) copy.
        offensive = dup
        Truffle.privately do
          offensive.__permute__(num, perm, 0, used, &block)
        end
      else
        __permute__(num, perm, 0, used, &block)
      end
    end

    self
  end

  def permutation_size(num)
    n = self.size
    if undefined.equal? num
      k = self.size
    else
      k = Truffle::Type.coerce_to_collection_index num
    end
    descending_factorial(n, k)
  end
  private :permutation_size

  def descending_factorial(from, how_many)
    cnt = how_many >= 0 ? 1 : 0
    while (how_many) > 0
      cnt = cnt*(from)
      from -= 1
      how_many -= 1
    end
    cnt
  end
  private :descending_factorial

  def __permute__(num, perm, index, used, &block)
    # Recursively compute permutations of r elements of the set [0..n-1].
    # When we have a complete permutation of array indexes, copy the values
    # at those indexes into a new array and yield that array.
    #
    # num: the number of elements in each permutation
    # perm: the array (of size num) that we're filling in
    # index: what index we're filling in now
    # used: an array of booleans: whether a given index is already used
    #
    # Note: not as efficient as could be for big num.
    size.times do |i|
      unless used[i]
        perm[index] = i
        if index < num-1
          used[i] = true
          __permute__(num, perm, index+1, used, &block)
          used[i] = false
        else
          yield values_at(*perm)
        end
      end
    end
  end
  private :__permute__

  # Implementation notes: We build a block that will generate all the
  # combinations by building it up successively using "inject" and starting
  # with one responsible to append the values.
  def product(*args)
    args.map! { |x| Truffle::Type.coerce_to(x, Array, :to_ary) }

    # Check the result size will fit in an Array.
    sum = args.inject(size) { |n, x| n * x.size }

    unless TrufflePrimitive.integer_fits_into_long(sum)
      raise RangeError, 'product result is too large'
    end

    # TODO rewrite this to not use a tree of Proc objects.

    # to get the results in the same order as in MRI, vary the last argument first
    args.reverse!

    result = []
    args.push self

    outer_lambda = args.inject(result.method(:push)) do |trigger, values|
      -> partial do
        values.each do |val|
          trigger.call(partial.dup << val)
        end
      end
    end

    outer_lambda.call([])

    if block_given?
      result.each { |v| yield(v) }
      self
    else
      result
    end
  end

  def rassoc(obj)
    each do |elem|
      if elem.kind_of? Array and elem.at(1) == obj
        return elem
      end
    end

    nil
  end

  def repeated_combination(combination_size, &block)
    combination_size = combination_size.to_i
    unless block_given?
      return to_enum(:repeated_combination, combination_size) do
        repeated_combination_size(combination_size)
      end
    end

    if combination_size < 0
      # yield nothing
    else
      Truffle.privately do
        dup.compile_repeated_combinations(combination_size, [], 0, combination_size, &block)
      end
    end

    self
  end

  def compile_repeated_combinations(combination_size, place, index, depth, &block)
    if depth > 0
      (length - index).times do |i|
        place[combination_size-depth] = index + i
        compile_repeated_combinations(combination_size,place,index + i,depth-1, &block)
      end
    else
      yield place.map { |element| self[element] }
    end
  end

  private :compile_repeated_combinations

  def repeated_permutation(combination_size, &block)
    combination_size = combination_size.to_i
    unless block_given?
      return to_enum(:repeated_permutation, combination_size) do
        repeated_permutation_size(combination_size)
      end
    end

    if combination_size < 0
      # yield nothing
    elsif combination_size == 0
      yield []
    else
      Truffle.privately do
        dup.compile_repeated_permutations(combination_size, [], 0, &block)
      end
    end

    self
  end

  def repeated_permutation_size(combination_size)
    return 0 if combination_size < 0
    self.size ** combination_size
  end
  private :repeated_permutation_size

  def repeated_combination_size(combination_size)
    return 1 if combination_size == 0
    binomial_coefficient(combination_size, self.size + combination_size - 1)
  end
  private :repeated_combination_size

  def binomial_coefficient(comb, size)
    comb = size-comb if (comb > size-comb)
    return 0 if comb < 0
    descending_factorial(size, comb) / descending_factorial(comb, comb)
  end
  private :binomial_coefficient

  def combination_size(num)
    binomial_coefficient(num, self.size)
  end
  private :combination_size

  def compile_repeated_permutations(combination_size, place, index, &block)
    length.times do |i|
      place[index] = i
      if index < (combination_size-1)
        compile_repeated_permutations(combination_size, place, index + 1, &block)
      else
        yield place.map { |element| self[element] }
      end
    end
  end
  private :compile_repeated_permutations

  def reverse
    Array.new dup.reverse!
  end

  def reverse_each
    return to_enum(:reverse_each) { size } unless block_given?

    i = size - 1
    while i >= 0
      yield at(i)
      i -= 1
    end
    self
  end

  def rindex(obj=undefined)
    if undefined.equal?(obj)
      return to_enum(:rindex, obj) unless block_given?

      i = size - 1
      while i >= 0
        return i if yield at(i)

        # Compensate for the array being modified by the block
        i = size if i > size

        i -= 1
      end
    else
      warn 'given block not used', uplevel: 1 if block_given?

      i = size - 1
      while i >= 0
        return i if at(i) == obj
        i -= 1
      end
    end
    nil
  end

  def rotate(n=1)
    n = Truffle::Type.coerce_to_collection_index n

    len = self.length
    return Array.new(self) if len <= 1

    n = n % len
    return Array.new(self) if n == 0
    TrufflePrimitive.array_rotate self, n
  end

  def rotate!(n=1)
    n = Truffle::Type.coerce_to_collection_index n
    Truffle.check_frozen

    len = self.length
    return self if len <= 1

    n = n % len
    return self if n == 0
    TrufflePrimitive.array_rotate_inplace self, n
  end

  class SampleRandom
    def initialize(rng)
      @rng = rng
    end

    def rand(size)
      random = Truffle::Type.coerce_to_collection_index @rng.rand(size)
      raise RangeError, 'random value must be >= 0' if random < 0
      raise RangeError, 'random value must be less than Array size' unless random < size

      random
    end
  end

  def sample(count=undefined, options=undefined)
    return at Kernel.rand(size) if undefined.equal? count

    if undefined.equal? options
      if o = Truffle::Type.rb_check_convert_type(count, Hash, :to_hash)
        options = o
        count = nil
      else
        options = nil
        count = Truffle::Type.coerce_to_collection_index count
      end
    else
      count = Truffle::Type.coerce_to_collection_index count
      options = Truffle::Type.coerce_to options, Hash, :to_hash
    end

    if count and count < 0
      raise ArgumentError, 'count must be greater than 0'
    end

    rng = options[:random] if options
    if rng and rng.respond_to? :rand
      rng = SampleRandom.new rng
    else
      rng = Kernel
    end

    return at rng.rand(size) unless count

    count = size if count > size

    case count
    when 0
      return []
    when 1
      return [at(rng.rand(size))]
    when 2
      i = rng.rand(size)
      j = rng.rand(size)
      if i == j
        j = i == 0 ? i + 1 : i - 1
      end
      return [at(i), at(j)]
    else
      sample_many(count, rng)
    end
  end

  def sample_many(count, rng)
    if size / count > 3
      abandon = false

      result = Array.new count
      i = 1

      result[0] = rng.rand(size)
      while i < count
        k = rng.rand(size)

        spin = false
        spin_count = 0

        while true # rubocop:disable Lint/LiteralAsCondition
          j = 0
          while j < i
            if k == result[j]
              spin = true
              break
            end

            j += 1
          end

          if spin
            if (spin_count += 1) > 100
              abandon = true
              break
            end

            k = rng.rand(size)
          else
            break
          end
        end

        break if abandon

        result[i] = k

        i += 1
      end

      unless abandon
        i = 0
        while i < count
          result[i] = at result[i]
          i += 1
        end

        return result
      end
    end

    result = Array.new(self)

    count.times do |c|
      Truffle.privately { result.swap c, rng.rand(size) }
    end

    count == size ? result : result[0, count]
  end
  private :sample_many

  def select!(&block)
    return to_enum(:select!) { size } unless block_given?

    Truffle.check_frozen

    ary = select(&block)
    TrufflePrimitive.steal_array_storage(self, ary) unless size == ary.size
  end

  alias_method :filter!, :select!

  def shuffle(options = undefined)
    return dup.shuffle!(options) if instance_of? Array
    Array.new(self).shuffle!(options)
  end

  def shuffle!(options = undefined)
    Truffle.check_frozen

    random_generator = Kernel

    unless undefined.equal? options
      options = Truffle::Type.coerce_to options, Hash, :to_hash
      random_generator = options[:random] if options[:random].respond_to?(:rand)
    end

    size.times do |i|
      r = i + random_generator.rand(size - i).to_int
      raise RangeError, "random number too big #{r - i}" if r < 0 || r >= size
      swap(i, r)
    end
    self
  end

  def drop(n)
    n = Truffle::Type.coerce_to_collection_index n
    raise ArgumentError, 'attempt to drop negative size' if n < 0

    new_size = size - n
    return [] if new_size <= 0

    self[n..-1]
  end

  def sort_by!(&block)
    Truffle.check_frozen

    return to_enum(:sort_by!) { size } unless block_given?

    TrufflePrimitive.steal_array_storage(self, sort_by(&block))
  end

  def to_a
    if self.instance_of? Array
      self
    else
      Array.new(self)
    end
  end

  def to_ary
    self
  end

  def to_h
    h = Hash.new
    each_with_index do |elem, i|
      elem = yield(elem) if block_given?
      unless elem.respond_to?(:to_ary)
        raise TypeError, "wrong element type #{elem.class} at #{i} (expected array)"
      end

      ary = elem.to_ary
      if ary.size != 2
        raise ArgumentError, "wrong array length at #{i} (expected 2, was #{ary.size})"
      end

      h[ary[0]] = ary[1]
    end
    h
  end

  def transpose
    return [] if empty?

    out = []
    max = nil

    each do |ary|
      ary = Truffle::Type.coerce_to ary, Array, :to_ary
      max ||= ary.size

      # Catches too-large as well as too-small (for which #fetch would suffice)
      raise IndexError, 'All arrays must be same length' if ary.size != max

      ary.size.times do |i|
        entry = (out[i] ||= [])
        entry << ary.at(i)
      end
    end

    out
  end

  def union(*others)
    res = Array.new(self).uniq
    others.each { |other| res = res | other }
    res
  end

  def unshift(*values)
    Truffle.check_frozen

    self[0, 0] = values

    self
  end

  alias_method :prepend, :unshift

  def values_at(*args)
    out = []

    args.each do |elem|
      # Cannot use #[] because of subtly different errors
      if elem.kind_of? Range
        finish = Truffle::Type.coerce_to_collection_index elem.last
        start = Truffle::Type.coerce_to_collection_index elem.first

        start += size if start < 0
        next if start < 0

        finish += size if finish < 0
        finish -= 1 if elem.exclude_end?

        next if finish < start

        start.upto(finish) { |i| out << at(i) }

      else
        i = Truffle::Type.coerce_to_collection_index elem
        out << at(i)
      end
    end

    out
  end

  def zip(*others)
    if !block_given? and others.size == 1 and Array === others[0]
      return TrufflePrimitive.array_zip self, others[0]
    end

    out = Array.new(size) unless block_given?

    others = others.map do |other|
      if other.respond_to?(:to_ary)
        other.to_ary
      else
        other.to_enum :each
      end
    end

    size.times do |i|
      tuple = [at(i)]
      others.each do |other|
        tuple << case other
                 when Array
                   other.at(i)
                 else
                   begin
                     other.next
                   rescue StopIteration
                     nil # the enumerator could change between next? and next leading to StopIteration
                   end
                 end
      end

      if block_given?
        yield tuple
      else
        out[i] = tuple
      end
    end

    if block_given?
      nil
    else
      out
    end
  end

  # Helper to recurse through flattening since the method
  # is not allowed to recurse itself. Detects recursive structures.
  def recursively_flatten(array, out, max_levels = -1)
    modified = false

    # Strict equality since < 0 means 'infinite'
    if max_levels == 0
      out.concat(array)
      return false
    end

    max_levels -= 1
    recursion = Thread.detect_recursion(array) do
      array = Truffle::Type.coerce_to(array, Array, :to_ary)

      i = 0
      size = array.size

      while i < size
        o = array.at i

        tmp = Truffle::Type.rb_check_convert_type(o, Array, :to_ary)
        if tmp.nil?
          out << o
        else
          modified = true
          recursively_flatten tmp, out, max_levels
        end

        i += 1
      end
    end

    raise ArgumentError, 'tried to flatten recursive array' if recursion
    modified
  end
  private :recursively_flatten

  private def sort_fallback(&block)
    # Use this instead of #dup as we want an instance of Array
    sorted = Array.new(self)

    Truffle.privately do
      if block
        sorted.mergesort_block!(block)
      else
        sorted.mergesort!
      end
    end
    sorted
  end

  # Non-recursive sort using a temporary array for scratch storage.
  # This is a hybrid mergesort; it's hybrid because for short runs under
  # 8 elements long we use insertion sort and then merge those sorted
  # runs back together.
  def mergesort!
    width = 7
    source = self
    scratch = Array.new(size, at(0))

    # do a pre-loop to create a bunch of short sorted runs; isort on these
    # 7-element sublists is more efficient than doing merge sort on 1-element
    # sublists
    left = 0
    finish = size
    while left < finish
      right = left + width
      right = right < finish ? right : finish
      last = left + (2 * width)
      last = last < finish ? last : finish

      isort!(left, right)
      isort!(right, last)

      left += 2 * width
    end

    # now just merge together those sorted lists from the prior loop
    width = 7
    while width < size
      left = 0
      while left < finish
        right = left + width
        right = right < finish ? right : finish
        last = left + (2 * width)
        last = last < finish ? last : finish

        bottom_up_merge(left, right, last, source, scratch)
        left += 2 * width
      end

      source, scratch = scratch, source
      width *= 2
    end

    TrufflePrimitive.steal_array_storage(self, source)

    self
  end
  private :mergesort!

  def bottom_up_merge(left, right, last, source, scratch)
    left_index = left
    right_index = right
    i = left

    while i < last
      left_element = source.at(left_index)
      right_element = source.at(right_index)

      if left_index < right && (right_index >= last || (left_element <=> right_element) <= 0)
        scratch[i] = left_element
        left_index += 1
      else
        scratch[i] = right_element
        right_index += 1
      end

      i += 1
    end
  end
  private :bottom_up_merge

  def mergesort_block!(block)
    width = 7
    source = self
    scratch = Array.new(size, at(0))

    left = 0
    finish = size
    while left < finish
      right = left + width
      right = right < finish ? right : finish
      last = left + (2 * width)
      last = last < finish ? last : finish

      isort_block!(left, right, block)
      isort_block!(right, last, block)

      left += 2 * width
    end

    width = 7
    while width < size
      left = 0
      while left < finish
        right = left + width
        right = right < finish ? right : finish
        last = left + (2 * width)
        last = last < finish ? last : finish

        bottom_up_merge_block(left, right, last, source, scratch, block)
        left += 2 * width
      end

      source, scratch = scratch, source
      width *= 2
    end

    TrufflePrimitive.steal_array_storage(self, source)

    self
  end
  private :mergesort_block!

  def bottom_up_merge_block(left, right, last, source, scratch, block)
    left_index = left
    right_index = right
    i = left

    while i < last
      left_element = source.at(left_index)
      right_element = source.at(right_index)

      if left_index < right && (right_index >= last || block.call(left_element, right_element) <= 0)
        scratch[i] = left_element
        left_index += 1
      else
        scratch[i] = right_element
        right_index += 1
      end

      i += 1
    end
  end
  private :bottom_up_merge_block

  # Insertion sort in-place between the given indexes.
  def isort!(left, right)
    i = left + 1

    while i < right
      j = i

      while j > left
        jp = j - 1
        el1 = at(jp)
        el2 = at(j)

        unless cmp = (el1 <=> el2)
          raise ArgumentError, "comparison of #{el1.inspect} with #{el2.inspect} failed (#{j})"
        end

        break unless cmp > 0

        self[j] = el1
        self[jp] = el2

        j = jp
      end

      i += 1
    end
  end
  private :isort!

  # Insertion sort in-place between the given indexes using a block.
  def isort_block!(left, right, block)
    i = left + 1

    while i < right
      j = i

      while j > left
        el1 = at(j - 1)
        el2 = at(j)
        block_result = block.call(el1, el2)

        if block_result.nil?
          raise ArgumentError, 'block returned nil'
        elsif block_result > 0
          self[j] = el1
          self[j - 1] = el2
          j -= 1
        else
          break
        end
      end

      i += 1
    end
  end
  private :isort_block!

  def reverse!
    Truffle.check_frozen
    return self unless size > 1

    i = 0
    while i < size / 2
      swap i, size-i-1
      i += 1
    end

    self
  end

  def slice!(start, length=undefined)
    Truffle.check_frozen

    if undefined.equal? length
      if start.kind_of? Range
        range = start
        out = self[range]

        range_start = Truffle::Type.coerce_to_collection_index range.begin
        if range_start < 0
          range_start = range_start + size
        end

        range_end = Truffle::Type.coerce_to_collection_index range.end
        if range_end < 0
          range_end = range_end + size
        elsif range_end >= size
          range_end = size - 1
          range_end += 1 if range.exclude_end?
        end

        range_length = range_end - range_start
        range_length += 1 unless range.exclude_end?
        range_end    -= 1 if     range.exclude_end?

        if range_start < size && range_start >= 0 && range_end < size && range_end >= 0 && range_length > 0
          delete_range(range_start, range_length)
        end
      else
        # make sure that negative values are not passed through to the
        # []= assignment
        start = Truffle::Type.coerce_to_collection_index start
        start = start + size if start < 0

        # This is to match the MRI behaviour of not extending the array
        # with nil when specifying an index greater than the length
        # of the array.
        return out unless start >= 0 and start < size

        out = at start

        # Check for shift style.
        if start == 0
          self[0] = nil
          self.shift
        else
          delete_range(start, 1)
        end
      end
    else
      start = Truffle::Type.coerce_to_collection_index start
      length = Truffle::Type.coerce_to_collection_length length
      return nil if length < 0

      out = self[start, length]

      if start < 0
        start = size + start
      end
      if start + length > size
        length = size - start
      end

      if start < size && start >= 0
        delete_range(start, length)
      end
    end

    out
  end

  def delete_range(index, del_length)
    reg_start = index + del_length
    reg_length = size - reg_start
    if reg_start <= size
      # copy tail
      self[index, reg_length] = self[reg_start, reg_length]

      self.pop(del_length)
    end
  end
  private :delete_range

  def uniq(&block)
    copy_of_same_class = dup
    result = super(&block)
    TrufflePrimitive.steal_array_storage(copy_of_same_class, result)
    copy_of_same_class
  end

  def uniq!(&block)
    Truffle.check_frozen
    result = uniq(&block)

    if self.size == result.size
      nil
    else
      TrufflePrimitive.steal_array_storage(self, result)
      self
    end
  end

  def sort!(&block)
    Truffle.check_frozen

    TrufflePrimitive.steal_array_storage(self, sort(&block))
  end

  private

  def swap(a, b)
    temp = at(a)
    self[a] = at(b)
    self[b] = temp
  end
end
