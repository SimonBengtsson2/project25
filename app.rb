require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require 'sinatra/reloader' if development?

enable :sessions

# Connect to the database
DB = SQLite3::Database.new('Cards.db')
DB.results_as_hash = true

# Home route
get '/' do
  slim :home, layout: :layout
end

# Merge route
get '/merge' do
  @user_cards = DB.execute("SELECT * FROM user_cards WHERE user_id = ?", session[:user_id])
  slim :merge, layout: :layout
end

post '/merge' do
  card_id = params[:card_id].to_i

  # Check if the user has at least 3 of this card
  card = DB.execute("SELECT * FROM user_cards WHERE user_id = ? AND card_id = ?", session[:user_id], card_id).first
  if card && card['quantity'] >= 3
    new_stars = card['stars'] + 1
    DB.execute("UPDATE user_cards SET quantity = quantity - 2 WHERE user_id = ? AND card_id = ?", session[:user_id], card_id)
    DB.execute("UPDATE user_cards SET stars = ? WHERE user_id = ? AND card_id = ?", new_stars, session[:user_id], card_id)
  end

  redirect '/merge'
end

# Pack route
get '/pack' do
  @user_currency = DB.execute("SELECT currency FROM users WHERE id = ?", session[:user_id]).first['currency']
  slim :pack, layout: :layout
end

post '/buy_pack' do
  pack_type = params[:pack_type]
  cost = pack_type == 'standard' ? 100 : 500
  user_currency = DB.execute("SELECT currency FROM users WHERE id = ?", session[:user_id]).first['currency']

  if user_currency >= cost
    DB.execute("UPDATE users SET currency = currency - ? WHERE id = ?", cost, session[:user_id])
    # Logic to add random cards to user collection
  end

  redirect '/pack'
end

# Collection route
get '/collection' do
  @user_cards = DB.execute("SELECT * FROM user_cards WHERE user_id = ?", session[:user_id])
  slim :collection, layout: :layout
end

# Currency route
get '/currency' do
  @user_currency = DB.execute("SELECT currency FROM users WHERE id = ?", session[:user_id]).first['currency']
  slim :currency, layout: :layout
end

post '/buy_currency' do
  amount = params[:amount].to_i
  DB.execute("UPDATE users SET currency = currency + ? WHERE id = ?", amount, session[:user_id])
  redirect '/currency'
end

# Settings route
get '/settings' do
  @user = DB.execute("SELECT * FROM users WHERE id = ?", session[:user_id]).first
  slim :settings, layout: :layout
end

post '/update_settings' do
  username = params[:username]
  password = params[:password]
  profile_pic = params[:profile_pic]

  if password.strip != ''
    hashed_password = BCrypt::Password.create(password)
    DB.execute("UPDATE users SET username = ?, password = ? WHERE id = ?", username, hashed_password, session[:user_id])
  else
    DB.execute("UPDATE users SET username = ? WHERE id = ?", username, session[:user_id])
  end

  redirect '/settings'
end