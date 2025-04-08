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
before '/collection' do
  redirect '/login' unless session[:user_id]
end

before '/merge' do
  redirect '/login' unless session[:user_id]
end
# Pack route
get '/pack' do
  slim :pack, layout: :layout
end

post '/open_pack' do
  redirect '/login' unless session[:user_id]

  # Define probabilities for each star level
  probabilities = {
    1 => 60, # 60% chance for 1-star cards
    2 => 25, # 25% chance for 2-star cards
    3 => 10, # 10% chance for 3-star cards
    4 => 4,  # 4% chance for 4-star cards
    5 => 1   # 1% chance for 5-star cards
  }

  # Normalize probabilities
  total_probability = probabilities.values.sum
  normalized_probabilities = probabilities.transform_values { |v| v.to_f / total_probability }

  # Fetch all cards from the database
  all_cards = DB.execute("SELECT * FROM Card")

  # Generate 10 random cards
  random_cards = 10.times.map do
    # Randomly select a star level based on probabilities
    random_star = probabilities.keys.find do |star|
      rand < normalized_probabilities[star]
    end

    # Select a random card with the chosen star level
    eligible_cards = all_cards.select { |card| card['stars'] == random_star }

    # If no cards are found for the selected star level, skip this iteration
    next if eligible_cards.empty?

    eligible_cards.sample
  end.compact # Remove any nil values in case no cards were found

  # Add the cards to the user's collection
  random_cards.each do |card|
    existing_card = DB.execute("SELECT * FROM Collection WHERE user_id = ? AND card_id = ?", [session[:user_id], card['card_id']]).first
    if existing_card
      DB.execute("UPDATE Collection SET quantity = quantity + 1 WHERE user_id = ? AND card_id = ?", [session[:user_id], card['card_id']])
    else
      DB.execute("INSERT INTO Collection (user_id, card_id, quantity) VALUES (?, ?, 1)", [session[:user_id], card['card_id']])
    end
  end

  # Pass the cards to the view
  @new_cards = random_cards
  slim :pack_result, layout: :layout
end
# Merge route
get '/merge' do
  # Fetch all cards in the user's collection
  @user_cards = DB.execute("
    SELECT Collection.card_id, Card.card_name, Card.stars, Card.picture
    FROM Collection
    JOIN Card ON Collection.card_id = Card.card_id
    WHERE Collection.user_id = ?
    ORDER BY Card.card_name", session[:user_id]) # Use the logged-in user's ID

  @error = session.delete(:error) # Retrieve and clear the error message
  slim :merge, layout: :layout
end

post '/merge' do
  # Retrieve the selected card IDs from the form
  card_ids = [params[:card_id_1], params[:card_id_2], params[:card_id_3]].map(&:to_i)

  # Ensure all selected cards are the same
  placeholders = (["?"] * card_ids.size).join(", ") # Dynamically create placeholders (?, ?, ?)
  cards = DB.execute("SELECT * FROM Card WHERE card_id IN (#{placeholders})", card_ids)
  unless cards.uniq { |card| [card['card_name'], card['stars']] }.size == 1
    session[:error] = "You must select three identical cards to merge."
    redirect '/merge'
  end

  card = cards.first

  # Check if the user owns the selected cards and has enough quantity
  card_ids.each do |card_id|
    user_card = DB.execute("SELECT * FROM Collection WHERE card_id = ? AND user_id = ?", [card_id, session[:user_id]]).first
    unless user_card
      session[:error] = "You do not own the selected cards."
      redirect '/merge'
    end
    if user_card['quantity'] < 3
      session[:error] = "You do not have enough of the selected card to merge. You need at least 3."
      redirect '/merge'
    end
  end

  # Deduct 3 cards for the selected card from the user's collection
  DB.execute("UPDATE Collection SET quantity = quantity - 3 WHERE card_id = ? AND user_id = ?", [card_ids.first, session[:user_id]])

  # Fetch the next-tier card
  next_tier_card = DB.execute("SELECT * FROM Card WHERE card_name = ? AND stars = ?", [card['card_name'], card['stars'] + 1]).first
  if next_tier_card.nil?
    session[:error] = "Next tier card does not exist. Please ensure the next-tier card is available in the database."
    redirect '/merge'
  end

  # Add the next-tier card to the user's collection
  existing_next_tier = DB.execute("SELECT * FROM Collection WHERE card_id = ? AND user_id = ?", [next_tier_card['card_id'], session[:user_id]]).first
  if existing_next_tier
    DB.execute("UPDATE Collection SET quantity = quantity + 1 WHERE card_id = ? AND user_id = ?", [next_tier_card['card_id'], session[:user_id]])
  else
    DB.execute("INSERT INTO Collection (user_id, card_id, quantity) VALUES (?, ?, 1)", [session[:user_id], next_tier_card['card_id']])
  end

  # Pass data to the view for animation or confirmation
  @merged_cards = [card] * 3
  @result_card = next_tier_card

  slim :merge_result, layout: :layout
end
get '/collection' do
  # Query to get all cards in the user's collection
  cards = DB.execute("
    SELECT Card.*, COALESCE(Collection.quantity, 0) AS quantity
    FROM Card
    LEFT JOIN Collection ON Card.card_id = Collection.card_id AND Collection.user_id = ?", session[:user_id])

  # Pass the cards to the view
  @cards = cards

  slim :collection, layout: :layout
end

# Registration route
get '/register' do
  slim :register, layout: :layout
end

post '/register' do
  username = params[:username]
  password = params[:password]
  profile_picture = params[:profile_picture]

  # Hash the password using BCrypt
  hashed_password = BCrypt::Password.create(password)

  # Insert the new user into the database
  begin
    DB.execute("INSERT INTO User (username, password, profile_picture) VALUES (?, ?, ?)", [username, hashed_password, profile_picture])
    redirect '/login'
  rescue SQLite3::ConstraintException
    @error = "Username already exists."
    slim :register, layout: :layout
  end
end
# Login route
get '/login' do
  slim :login, layout: :layout
end

post '/login' do
  username = params[:username]
  password = params[:password]

  # Fetch the user from the database
  user = DB.execute("SELECT * FROM User WHERE username = ?", [username]).first

  if user && BCrypt::Password.new(user['password']) == password
    session[:user_id] = user['user_id']
    redirect '/collection'
  else
    @error = "Invalid username or password."
    slim :login, layout: :layout
  end
end

# Logout route
get '/logout' do
  session.clear
  redirect '/login'
end

# Settings route
get '/settings' do
  redirect '/login' unless session[:user_id]

  @user = DB.execute("SELECT * FROM User WHERE user_id = ?", [session[:user_id]]).first
  slim :settings, layout: :layout
end

post '/update_settings' do
  redirect '/login' unless session[:user_id]

  username = params[:username]
  password = params[:password]
  profile_picture = params[:profile_picture]

  if password.strip != ''
    hashed_password = BCrypt::Password.create(password)
    DB.execute("UPDATE User SET username = ?, password = ?, profile_picture = ? WHERE user_id = ?", [username, hashed_password, profile_picture, session[:user_id]])
  else
    DB.execute("UPDATE User SET username = ?, profile_picture = ? WHERE user_id = ?", [username, profile_picture, session[:user_id]])
  end

  redirect '/settings'
end


post '/delete_user' do
  redirect '/login' unless session[:user_id]

  # Delete the user from the database
  DB.execute("DELETE FROM User WHERE user_id = ?", [session[:user_id]])

  # Clear the session and redirect to the login page
  session.clear
  redirect '/login'
end