require "test_helper"

class ProofOfWorkTest < ActiveSupport::TestCase
  test "generates a number using the inclusive range from 0 to 10" do
    [0, 5, 10].each do |number|
      proof = ProofOfWork.new
      ranges = []
      proof.define_singleton_method(:rand) do |range|
        ranges << range
        number
      end

      assert_equal number, proof.generate_number
      assert_equal [0..10], ranges
      assert proof.matches?(number)
    end
  end

  test "only the matching integer succeeds for every possible target" do
    (0..10).each do |target|
      proof = proof_with_number(target)

      assert proof.matches?(target)
      ((0..10).to_a - [target]).each do |guess|
        assert_not proof.matches?(guess), "#{guess} must not match #{target}"
      end
    end
  end

  test "nothing matches before a number has been generated" do
    proof = ProofOfWork.new

    [nil, 0, 5, 10].each { |guess| assert_not proof.matches?(guess) }
  end

  test "rejects nonintegers and numbers outside the range" do
    proof = proof_with_number(5)

    [nil, "5", 5.0, true, false, [], {}, -1, 11].each do |guess|
      assert_not proof.matches?(guess)
    end
  end

  test "checking keeps the current number until generation is requested again" do
    proof = proof_with_number(3)

    proof.define_singleton_method(:rand) do |*|
      raise "Checking a guess must not generate a number"
    end
    assert_not proof.matches?(8)
    assert proof.matches?(3)
    assert proof.matches?(3)

    proof.define_singleton_method(:rand) { |_range| 8 }
    proof.generate_number
    assert_not proof.matches?(3)
    assert proof.matches?(8)
  end

  private

  def proof_with_number(number)
    proof = ProofOfWork.new
    proof.define_singleton_method(:rand) { |_range| number }
    proof.generate_number
    proof
  end
end
