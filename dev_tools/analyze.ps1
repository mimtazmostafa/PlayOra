Set-Location 'c:\Users\Asus\Playora\playhub_bd'
$paths = @(
  'lib\data\models\game_model.dart',
  'lib\features\game_player\game_player_screen.dart',
  'lib\features\game_player\widgets\coming_soon_module.dart',
  'lib\features\games\widgets\game_card.dart',
  'lib\features\games\game_details_screen.dart'
)
& flutter analyze @paths