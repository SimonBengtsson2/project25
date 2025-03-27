require 'fileutils'

# Generate SQL for inserting cards into the database
def generate_card_sql
  # Get all image files from the img/Cards folder
  card_images = Dir.glob('public/img/Cards/**/*.{jpg,png,gif}')

  # Initialize an array to store SQL statements
  sql_statements = []

  # Process each image file
  card_images.each do |image_path|
    # Extract character name and star level from the file name
    file_name = File.basename(image_path, File.extname(image_path)) # e.g., "Cho1"
    match_data = file_name.match(/([a-zA-Z]+)(\d)/)

    # Skip files that don't match the expected format
    next unless match_data

    character_name, star_level = match_data.captures # e.g., "Cho", "1"

    # Format the card name and other attributes
    card_name = "#{character_name.capitalize} #{star_level}-star"
    card_type = 'Champion' # Default card type
    stars = star_level.to_i # Convert star level to integer
    picture = image_path.sub('public/', '') # Remove 'public/' prefix for Sinatra

    # Generate the SQL statement
    sql_statements << "INSERT INTO Card (card_name, card_type, stars, picture) VALUES ('#{card_name}', '#{card_type}', #{stars}, '#{picture}');"
  end

  # Output the SQL statements to the terminal
  puts sql_statements.join("\n")
end

# Call the function to generate and output the SQL
generate_card_sql