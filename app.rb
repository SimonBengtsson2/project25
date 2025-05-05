require 'sinatra'
require 'slim'
require 'bcrypt'
require_relative './model.rb'
require 'sinatra/reloader' if development?
ADMIN_KEY = "123"
enable :sessions
helpers do
  def validate_registration(params)
    errors = []
    errors << "Username cannot be empty" if params[:username].strip.empty?
    errors << "Password cannot be empty" if params[:password].strip.empty?
    errors << "Email must contain @" unless params[:email].include?("@")
    errors
  end
  helpers do
    def validate_presence(params, required_fields)
      errors = []
      required_fields.each do |field|
        errors << "#{field.capitalize} cannot be empty" if params[field].nil? || params[field].strip.empty?
      end
      errors
    end
  end
  helpers do
    def current_user
      @current_user ||= find_user_by_id(session[:user_id])
    end
  end
# Ensure the user is logged in before accessing protected routes



  def authorized?(required_role)
    roles = { guest: 0, user: 1, admin: 2 }
    roles[current_user['role'].to_sym] >= roles[required_role]
  end
end
helpers do
  def current_user
    @current_user ||= find_user_by_id(session[:user_id])
  end
end
# Restrict access to admin-only routes
before '/admin/*' do
  halt 403, "Forbidden" unless authorized?(:admin)
end
# Ensure the user owns the resource before updating or deleting it
before '/resources/:id/*' do
  resource = find_resource(params[:id])
  halt 403, "Forbidden" unless resource['user_id'] == session[:user_id]
end
before do
  protected_routes = ['/cards', '/cards/merge', '/admin/cards', '/admin/cards/add', '/admin/cards/remove']
  if protected_routes.include?(request.path_info) && session[:user_id].nil?
    redirect '/sessions/new'
  end
end

# Home route
get '/' do
  slim :home, layout: :layout
end
# Login page
get '/sessions/new' do
  slim :login, layout: :layout
end

# Log in (create session)
post '/sessions' do
  errors = validate_presence(params, ['username', 'password'])
  if errors.any?
    @error = errors.join(", ")
    slim :login, layout: :layout
  else
    username = params[:username]
    password = params[:password]

    user = find_user_by_username(username)

    if user && BCrypt::Password.new(user['password']) == password
      session[:user_id] = user['user_id']
      redirect '/cards'
    else
      @error = "Invalid username or password."
      slim :login, layout: :layout
    end
  end
end
# Log out (delete session)
delete '/sessions' do
  session.clear
  redirect '/sessions/new'
end
# Registration page
get '/users/new' do
  slim :register, layout: :layout
end

# Register a new user
post '/users' do
  errors = validate_presence(params, ['username', 'password'])
  if errors.any?
    @error = errors.join(", ")
    slim :register, layout: :layout
  else
    role = params[:admin_key] == ADMIN_KEY ? 'admin' : 'user'
    create_user(params[:username], params[:password], params[:email], role)
    redirect '/sessions/new'
  end
end
# Pack opening page
get '/packs/new' do
  redirect '/sessions/new' unless session[:user_id]
  slim :pack, layout: :layout
end

# Open a pack
post '/packs' do
  redirect '/sessions/new' unless session[:user_id]

  probabilities = { 1 => 60, 2 => 25, 3 => 10, 4 => 4, 5 => 1 }
  total_probability = probabilities.values.sum
  normalized_probabilities = probabilities.transform_values { |v| v.to_f / total_probability }

  random_cards = generate_random_cards(probabilities, 10)

  random_cards.each do |card|
    add_card_to_collection(session[:user_id], card['card_id'])
  end

  @new_cards = random_cards
  slim :pack_result, layout: :layout
end

get '/cards/merge' do
  redirect '/sessions/new' unless session[:user_id]

  @user_cards = all_cards_for_user(session[:user_id]) # Fetch user's cards from the model
  slim :merge, layout: :layout
end

# Merge cards
post '/cards/merge' do
  errors = validate_presence(params, ['card_id_1', 'card_id_2', 'card_id_3'])
  if errors.any?
    @error = "You must select 3 cards to merge."
    @user_cards = all_cards_for_user(session[:user_id]) # Ensure user cards are available for the view
    slim :merge, layout: :layout
  else
    card_ids = [params[:card_id_1], params[:card_id_2], params[:card_id_3]].map(&:to_i)

    # Ensure all selected cards are the same
    placeholders = (["?"] * card_ids.size).join(", ")
    cards = DB.execute("SELECT * FROM Card WHERE card_id IN (#{placeholders})", card_ids)

    unless cards.uniq { |card| [card['card_name'], card['stars']] }.size == 1
      @error = "You must select three identical cards to merge."
      @user_cards = all_cards_for_user(session[:user_id]) # Ensure user cards are available for the view
      slim :merge, layout: :layout
    end

    card = cards.first

    # Check if the user owns the selected cards and has enough quantity
    unless can_merge_cards?(session[:user_id], card_ids)
      @error = "You do not have enough of the selected card to merge."
      @user_cards = all_cards_for_user(session[:user_id]) # Ensure user cards are available for the view
      slim :merge, layout: :layout
    end

    # Deduct the selected cards from the user's collection
    deduct_card_from_collection(session[:user_id], card_ids.first, 3)

    # Add the next-tier card to the user's collection
    next_tier_card = DB.execute("SELECT * FROM Card WHERE card_name = ? AND stars = ?", [card['card_name'], card['stars'] + 1]).first
    if next_tier_card.nil?
      @error = "Next tier card does not exist."
      @user_cards = all_cards_for_user(session[:user_id]) # Ensure user cards are available for the view
      slim :merge, layout: :layout
    end

    add_card_to_collection(session[:user_id], next_tier_card['card_id'])

    # Pass data to the view
    @merged_cards = [card] * 3
    @result_card = next_tier_card
    slim :merge_result, layout: :layout
  end
end
# View card collection
get '/cards' do
  redirect '/sessions/new' unless session[:user_id]

  @cards = all_cards_for_user(session[:user_id]) # Fetch user's cards from the model
  slim :collection, layout: :layout
end


get '/users/edit' do
  redirect '/sessions/new' unless session[:user_id]

  @user = current_user # Fetch the currently logged-in user
  slim :settings, layout: :layout
end
post '/users/edit' do
  errors = validate_presence(params, ['username'])
  if errors.any?
    @error = errors.join(", ")
    @user = current_user
    slim :settings, layout: :layout
  else
    update_user(session[:user_id], params[:username], params[:password])
    @message = "Your account has been updated successfully."
    redirect '/cards'
  end
end
# Route to display the upgrade page
get '/users/upgrade' do
  redirect '/sessions/new' unless session[:user_id]
  slim :upgrade, layout: :layout
end

# Route to handle admin upgrade
post '/users/upgrade' do
  errors = validate_presence(params, ['admin_key'])
  if errors.any?
    @error = errors.join(", ")
    slim :upgrade, layout: :layout
  else
    if params[:admin_key] == ADMIN_KEY
      DB.execute("UPDATE User SET role = 'admin' WHERE user_id = ?", [session[:user_id]])
      @message = "You are now an admin!"
    else
      @error = "Invalid admin key."
    end
    slim :upgrade, layout: :layout
  end
end
# Admin page to manage card collection
get '/admin/cards' do
  redirect '/sessions/new' unless session[:user_id]
  halt 403, "Forbidden" unless current_user['role'] == 'admin'

  @cards = all_cards_for_user(session[:user_id]) # Fetch admin's cards
  slim :admin_cards, layout: :layout
end

# Add a card to the admin's collection
post '/admin/cards/add' do
  errors = validate_presence(params, ['card_id', 'quantity'])
  if errors.any?
    @error = "You must select a card and specify a quantity to add."
    @cards = all_cards_for_user(session[:user_id]) # Ensure admin's cards are available for the view
    @all_cards = DB.execute("SELECT * FROM Card") # Fetch all cards for the dropdown
    slim :admin_cards, layout: :layout
  else
    card_id = params[:card_id].to_i
    quantity = params[:quantity].to_i

    add_card_to_collection(session[:user_id], card_id, quantity)
    redirect '/admin/cards'
  end
end
post '/admin/cards/remove' do
  errors = validate_presence(params, ['card_id', 'quantity'])
  if errors.any?
    @error = "You must select a card and specify a quantity to remove."
    @cards = all_cards_for_user(session[:user_id]) # Ensure admin's cards are available for the view
    @all_cards = DB.execute("SELECT * FROM Card") # Fetch all cards for the dropdown
    slim :admin_cards, layout: :layout
  else
    card_id = params[:card_id].to_i
    quantity = params[:quantity].to_i

    deduct_card_from_collection(session[:user_id], card_id, quantity)
    redirect '/admin/cards'
  end
end