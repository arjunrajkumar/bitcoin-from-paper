class ProofOfWork
  def generate_number
    @current_number = rand(0..10)
  end

  def matches?(received_number)
    received_number.is_a?(Integer) && received_number == @current_number
  end
end
