require 'sqlite3'
require 'bcrypt'

# Connect to the database
DB = SQLite3::Database.new(File.join(Dir.pwd, 'db', 'Cards.db'))
DB.results_as_hash = true

# User-related methods
def find_user_by_username(username)
  DB.execute("SELECT * FROM User WHERE username = ?", [username]).first
end

def find_user_by_id(id)
  DB.execute("SELECT * FROM User WHERE user_id = ?", [id]).first
end

def create_user(username, password, role)
  hashed_password = BCrypt::Password.create(password)
  DB.execute("INSERT INTO User (username, password, role) VALUES (?, ?, ?)", 
             [username, hashed_password, role])
end

def update_user(user_id, username, password)
  if password.strip.empty?
    DB.execute("UPDATE User SET username = ? WHERE user_id = ?", [username, user_id])
  else
    hashed_password = BCrypt::Password.create(password)
    DB.execute("UPDATE User SET username = ?, password = ? WHERE user_id = ?", [username, hashed_password, user_id])
  end
end

def delete_user(id)
  DB.execute("DELETE FROM User WHERE user_id = ?", [id])
end

# Card-related methods
def all_cards
  DB.execute("SELECT * FROM Card")
end

def find_card_by_id(id)
  DB.execute("SELECT * FROM Card WHERE card_id = ?", [id]).first
end

def find_cards_by_star_level(star_level)
  DB.execute("SELECT * FROM Card WHERE stars = ?", [star_level])
end

# Collection-related methods
def find_collection_by_user_and_card(user_id, card_id)
  DB.execute("SELECT * FROM Collection WHERE user_id = ? AND card_id = ?", [user_id, card_id]).first
end

def add_card_to_collection(user_id, card_id, quantity)
  existing_card = DB.execute("SELECT * FROM Collection WHERE user_id = ? AND card_id = ?", [user_id, card_id]).first

  if existing_card
    DB.execute("UPDATE Collection SET quantity = quantity + ? WHERE user_id = ? AND card_id = ?", [quantity, user_id, card_id])
  else
    DB.execute("INSERT INTO Collection (user_id, card_id, quantity) VALUES (?, ?, ?)", [user_id, card_id, quantity])
  end
end




def deduct_card_from_collection(user_id, card_id, quantity)
  existing_card = DB.execute("SELECT * FROM Collection WHERE user_id = ? AND card_id = ?", [user_id, card_id]).first

  if existing_card && existing_card['quantity'] > quantity
    DB.execute("UPDATE Collection SET quantity = quantity - ? WHERE user_id = ? AND card_id = ?", [quantity, user_id, card_id])
  elsif existing_card && existing_card['quantity'] == quantity
    DB.execute("DELETE FROM Collection WHERE user_id = ? AND card_id = ?", [user_id, card_id])
  else
    raise "Not enough cards to remove"
  end
end
def all_cards_for_user(user_id)
    DB.execute("
      SELECT Card.card_id, Card.card_name, Card.stars, Card.picture, COALESCE(Collection.quantity, 0) AS quantity
      FROM Card
      LEFT JOIN Collection ON Card.card_id = Collection.card_id AND Collection.user_id = ?", [user_id])
  end
  def find_user_by_id(user_id)
    DB.execute("SELECT * FROM User WHERE user_id = ?", [user_id]).first
  end

  def can_merge_cards?(user_id, card_ids)
    card_ids.all? do |card_id|
      user_card = find_collection_by_user_and_card(user_id, card_id)
      user_card && user_card['quantity'] >= 3
    end
  end
 
 
  def generate_random_cards(probabilities, count)
    all_cards = all_cards()
    total_probability = probabilities.values.sum
    normalized_probabilities = probabilities.transform_values { |v| v.to_f / total_probability }
  
    count.times.map do
      random_star = probabilities.keys.find { |star| rand < normalized_probabilities[star] }
      eligible_cards = all_cards.select { |card| card['stars'] == random_star }
      eligible_cards.sample
    end.compact
  end

  def add_card_to_collection(user_id, card_id, quantity)
    existing_card = DB.execute("SELECT * FROM Collection WHERE user_id = ? AND card_id = ?", [user_id, card_id]).first
  
    if existing_card
      DB.execute("UPDATE Collection SET quantity = quantity + ? WHERE user_id = ? AND card_id = ?", [quantity, user_id, card_id])
    else
      DB.execute("INSERT INTO Collection (user_id, card_id, quantity) VALUES (?, ?, ?)", [user_id, card_id, quantity])
    end
  end
  
  def deduct_card_from_collection(user_id, card_id, quantity)
    existing_card = DB.execute("SELECT * FROM Collection WHERE user_id = ? AND card_id = ?", [user_id, card_id]).first
  
    if existing_card && existing_card['quantity'] > quantity
      DB.execute("UPDATE Collection SET quantity = quantity - ? WHERE user_id = ? AND card_id = ?", [quantity, user_id, card_id])
    elsif existing_card && existing_card['quantity'] == quantity
      DB.execute("DELETE FROM Collection WHERE user_id = ? AND card_id = ?", [user_id, card_id])
    else
      raise "Not enough cards to remove"
    end
  end
  def find_user_by_id(user_id)
    DB.execute("SELECT * FROM User WHERE user_id = ?", [user_id]).first
  end
  def authorized?(required_role)
    return false unless current_user # Return false if no user is logged in
    roles = { guest: 0, user: 1, admin: 2 }
    roles[current_user['role'].to_sym] >= roles[required_role]
  end