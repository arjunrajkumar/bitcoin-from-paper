require "test_helper"

class ProofOfWorkRoundTest < ActiveSupport::TestCase
  test "collects every guess before choosing the first matching entry" do
    events = []
    first = node_with_guess(4, events)
    second = node_with_guess(7, events)
    third = node_with_guess(7, events)
    proof = proof_with_number(7)
    proof.define_singleton_method(:matches?) do |number|
      events << [:check, number]
      super(number)
    end
    proof.define_singleton_method(:rand) { |*| raise "A matching guess needs no random winner" }

    assert_equal second, proof.find_winner([first, second, third])
    assert_equal [[:guess, first.id], [:guess, second.id], [:guess, third.id], [:check, 4], [:check, 7]], events
  end

  test "any participating node can win at random when every guess misses" do
    nodes = Array.new(3) { Node.create! }
    (0..10).each do |target|
      nodes.each { |node| node.define_singleton_method(:guess) { (target + 1) % 11 } }

      nodes.each_with_index do |expected_winner, index|
        proof = proof_with_number(target)
        limits = []
        proof.define_singleton_method(:rand) do |limit|
          limits << limit
          index
        end

        assert_equal expected_winner, proof.find_winner(nodes)
        assert_equal [3], limits
      end
    end
  end

  test "each node gets one guess even when its record appears more than once" do
    events = []
    first = node_with_guess(3, events)
    second = node_with_guess(7, events)
    same_node = Node.find(first.id)
    same_node.define_singleton_method(:guess) { raise "The same node cannot guess twice" }
    proof = proof_with_number(7)

    assert_equal second, proof.find_winner([first, first, same_node, second])
    assert_equal [[:guess, first.id], [:guess, second.id]], events
  end

  test "another call starts another round after every node has guessed" do
    events = []
    first = node_with_guess(7, events)
    second = node_with_guess(3, events)
    proof = proof_with_number(7)

    2.times { assert_equal first, proof.find_winner([first, second]) }
    assert_equal [[:guess, first.id], [:guess, second.id], [:guess, first.id], [:guess, second.id]], events
    assert proof.matches?(7)
  end

  test "uses stored nodes when no list is supplied" do
    node = Node.create!
    proof = proof_with_number(5)
    proof.define_singleton_method(:rand) { |_limit| 0 }

    assert_equal node, proof.find_winner
  end

  test "no nodes means no winner" do
    proof = proof_with_number(5)
    proof.define_singleton_method(:rand) { |*| raise "There is no node to select" }

    assert_nil proof.find_winner
    assert_nil proof.find_winner([])
  end

  test "requires a target before asking nodes to guess" do
    events = []
    node = node_with_guess(5, events)

    error = assert_raises(ArgumentError) { ProofOfWork.new.find_winner([node]) }
    assert_equal "Generate a number before starting a round", error.message
    assert_equal [], events
  end

  private

  def proof_with_number(number)
    proof = ProofOfWork.new
    proof.define_singleton_method(:rand) { |_range| number }
    proof.generate_number
    proof
  end

  def node_with_guess(number, events)
    node = Node.create!
    node.define_singleton_method(:guess) do
      events << [:guess, id]
      number
    end
    node
  end
end
