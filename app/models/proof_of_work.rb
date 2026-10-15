class ProofOfWork
  def generate_number
    @current_number = rand(ProtocolRules::PROOF_OF_WORK_NUMBER_RANGE)
  end

  def matches?(received_number)
    received_number.is_a?(Integer) && received_number == @current_number
  end

  def find_winner(nodes = Node.order(:id))
    raise ArgumentError, "Generate a number before starting a round" if @current_number.nil?

    answers = nodes.to_a.uniq.map { |node| [node, node.guess] }
    return nil if answers.empty?

    matching_answer = answers.find { |_node, number| matches?(number) }
    matching_answer ? matching_answer.first : answers[rand(answers.length)].first
  end
end
