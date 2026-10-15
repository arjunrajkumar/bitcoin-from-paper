require "test_helper"

class NodeTest < ActiveSupport::TestCase
  test "stores a separate identity for each node" do
    first = Node.create!
    second = Node.create!

    assert_equal first, Node.find(first.id)
    assert_not_equal first.id, second.id
  end

  test "guesses an integer from 0 through 10 inclusive" do
    (0..10).each do |number|
      node = Node.new
      ranges = []
      node.define_singleton_method(:rand) do |range|
        ranges << range
        number
      end

      assert_equal number, node.guess
      assert_equal [0..10], ranges
    end
  end
end
