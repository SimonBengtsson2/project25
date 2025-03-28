require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'sinatra/reloader' if development?

enable :sessions

# Connect to the database
DB = SQLite3::Database.new(File.join(Dir.pwd, 'db', 'Cards.db'))
DB.results_as_hash = true

# Home route
get '/' do
  slim :home, layout: :layout
end

# Pack route
get '/pack' do
  slim :pack, layout: :layout
end
# Merge route
get '/merge' do
  # Fetch all cards in user3's collection
  @user_cards = DB.execute("
    SELECT Collection.card_id, Collection.quantity, Card.card_name, Card.stars, Card.picture
    FROM Collection
    JOIN Card ON Collection.card_id = Card.card_id
    WHERE Collection.user_id = ?", 3) # Hardcoded user_id = 3

  slim :merge, layout: :layout
end
post '/merge' do
  card_ids = [params[:card_id_1], params[:card_id_2], params[:card_id_3]].map(&:to_i)

  # Ensure all selected cards are the same
  placeholders = (["?"] * card_ids.size).join(", ") # Dynamically create placeholders (?, ?, ?)
  cards = DB.execute("SELECT * FROM Card WHERE card_id IN (#{placeholders})", card_ids)
  halt 400, "You must select three identical cards to merge" unless cards.uniq { |card| [card['card_name'], card['stars']] }.size == 1

  card = cards.first

  # Check if the user has enough cards
  user_card = DB.execute("SELECT * FROM Collection WHERE card_id = ? AND user_id = ?", [card['card_id'], 3]).first
  halt 400, "Not enough cards to merge" unless user_card && user_card['quantity'] >= 3

  # Deduct 3 cards from the user's collection
  DB.execute("UPDATE Collection SET quantity = quantity - 3 WHERE card_id = ? AND user_id = ?", [card['card_id'], 3])

  # Fetch the next-tier card
  next_tier_card = DB.execute("SELECT * FROM Card WHERE card_name = ? AND stars = ?", [card['card_name'], card['stars'] + 1]).first
  if next_tier_card.nil?
    # If the next-tier card does not exist, create it dynamically (optional)
    halt 400, "Next tier card does not exist. Please ensure the next-tier card is available in the database."
  end

  # Add the next-tier card to the user's collection
  existing_next_tier = DB.execute("SELECT * FROM Collection WHERE card_id = ? AND user_id = ?", [next_tier_card['card_id'], 3]).first
  if existing_next_tier
    DB.execute("UPDATE Collection SET quantity = quantity + 1 WHERE card_id = ? AND user_id = ?", [next_tier_card['card_id'], 3])
  else
    DB.execute("INSERT INTO Collection (user_id, card_id, quantity) VALUES (?, ?, 1)", [3, next_tier_card['card_id']])
  end

  # Pass data to the view for animation
  @merged_cards = [card] * 3
  @result_card = next_tier_card

  slim :merge_result, layout: :layout
end
get '/collection' do
  # Query to get all cards from the database
  cards = DB.execute("SELECT * FROM Card ORDER BY card_name")

  # Pass the cards to the view
  @cards = cards

  slim :collection, layout: :layout
end




# Settings route
post '/update_settings' do
  username = params[:username]
  password = params[:password]
  profile_pic = params[:profile_pic]

  if password.strip != ''
    hashed_password = BCrypt::Password.create(password)
    DB.execute("UPDATE User SET username = ?, password = ? WHERE user_id = ?", username, hashed_password, 1) # Hardcoded user_id = 1
  else
    DB.execute("UPDATE User SET username = ? WHERE user_id = ?", username, 1) # Hardcoded user_id = 1
  end

  redirect '/settings'
end