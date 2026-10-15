// Word Master — clean Spelling-Bee style word game.
//
// Tap a tile to add it to the current selection. Tap a tile already in
// the selection to truncate back to that point. Tap Submit to lock in
// the selection if it forms a valid English word from the embedded
// dictionary. Shuffle rearranges the 12 letters. Hint reveals one
// still-missing word for 10 coins.
//
// The dictionary is a hand-curated ~500-word list embedded as a const
// (no asset file, no asset bundle load, ~5 KB total). That keeps the
// APK small while still producing 8+ valid matches per generated board.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

class SpellingBeeGame extends MiniGame {
  const SpellingBeeGame({
    super.key,
    required super.callbacks,
    this.dailyChallenge = false,
  });

  final bool dailyChallenge;

  @override
  State<SpellingBeeGame> createState() => _SpellingBeeState();
}

class _SpellingBeeState extends MiniGameState<SpellingBeeGame> {
  // ─── Embedded dictionary ─────────────────────────────────────────
  // 500 of the most common 3–6 letter English words. Used directly so
  // we don't need to ship an asset file. Keeping it lowercase + sorted
  // lets us binary-search instead of linear scan if needed later.
  static const Set<String> _dictionary = <String>{
    'ACE', 'ACT', 'ADD', 'AGE', 'AGO', 'AID', 'AIM', 'AIR', 'ALL', 'AND',
    'ANT', 'ANY', 'APE', 'APP', 'ARC', 'ARE', 'ARK', 'ARM', 'ART', 'ASH',
    'ASK', 'ATE', 'AWE', 'AXE', 'BAD', 'BAG', 'BAN', 'BAR', 'BAT', 'BAY',
    'BED', 'BEE', 'BET', 'BID', 'BIG', 'BIN', 'BIT', 'BOW', 'BOX', 'BOY',
    'BUD', 'BUG', 'BUN', 'BUS', 'BUT', 'BUY', 'CAB', 'CAN', 'CAP', 'CAR',
    'CAT', 'COP', 'COW', 'CRY', 'CUB', 'CUP', 'CUT', 'DAD', 'DAM', 'DAY',
    'DEW', 'DID', 'DIG', 'DIN', 'DIP', 'DOC', 'DOE', 'DOG', 'DOT', 'DRY',
    'DUB', 'DUE', 'DUG', 'DUN', 'DUO', 'DYE', 'EAR', 'EAT', 'EEL', 'EGG',
    'ELF', 'ELK', 'ELM', 'END', 'ERA', 'EVE', 'EWE', 'EYE', 'FAN', 'FAR',
    'FAT', 'FAX', 'FED', 'FEE', 'FEW', 'FIG', 'FIN', 'FIR', 'FIT', 'FIX',
    'FLY', 'FOB', 'FOG', 'FOR', 'FOX', 'FRY', 'FUN', 'FUR', 'GAB', 'GAG',
    'GAP', 'GAS', 'GEM', 'GET', 'GNU', 'GOB', 'GOD', 'GOT', 'GUM', 'GUN',
    'GUT', 'GUY', 'GYM', 'HAD', 'HAM', 'HAS', 'HAT', 'HAY', 'HEN', 'HER',
    'HEW', 'HID', 'HIM', 'HIP', 'HIS', 'HIT', 'HOB', 'HOG', 'HOP', 'HOT',
    'HOW', 'HUB', 'HUE', 'HUG', 'HUM', 'HUT', 'ICE', 'ICY', 'ILL', 'IMP',
    'INK', 'INN', 'ION', 'IRE', 'IRK', 'ITS', 'IVY', 'JAB', 'JAG', 'JAM',
    'JAR', 'JAW', 'JAY', 'JET', 'JIG', 'JOB', 'JOG', 'JOT', 'JOY', 'JUG',
    'JUT', 'KEG', 'KEN', 'KEY', 'KID', 'KIN', 'KIT', 'LAB', 'LAD', 'LAG',
    'LAP', 'LAW', 'LAY', 'LEA', 'LED', 'LEG', 'LET', 'LID', 'LIE', 'LIP',
    'LIT', 'LOG', 'LOT', 'LOW', 'LUG', 'MAD', 'MAN', 'MAP', 'MAR', 'MAT',
    'MAW', 'MAX', 'MAY', 'MEN', 'MET', 'MID', 'MIX', 'MOB', 'MOM', 'MOP',
    'MOW', 'MUD', 'MUG', 'MUM', 'NAB', 'NAG', 'NAP', 'NET', 'NEW', 'NIL',
    'NIT', 'NOD', 'NOR', 'NOT', 'NOW', 'NUB', 'NUN', 'NUT', 'OAK', 'OAR',
    'OAT', 'ODD', 'ODE', 'OFF', 'OFT', 'OHM', 'OIL', 'OLD', 'ONE', 'OPT',
    'ORB', 'ORE', 'OUR', 'OUT', 'OWE', 'OWL', 'OWN', 'PAD', 'PAL', 'PAN',
    'PAP', 'PAR', 'PAT', 'PAW', 'PAY', 'PEA', 'PEG', 'PEN', 'PEP', 'PER',
    'PET', 'PEW', 'PIE', 'PIG', 'PIN', 'PIP', 'PIT', 'PLY', 'POD', 'POP',
    'POT', 'POW', 'PRY', 'PUB', 'PUG', 'PUN', 'PUP', 'PUS', 'PUT', 'RAG',
    'RAM', 'RAN', 'RAP', 'RAT', 'RAW', 'RAY', 'RED', 'REF', 'REP', 'RIB',
    'RID', 'RIG', 'RIM', 'RIP', 'ROB', 'ROD', 'ROE', 'ROT', 'ROW', 'RUB',
    'RUG', 'RUM', 'RUN', 'RUT', 'RYE', 'SAD', 'SAG', 'SAP', 'SAT', 'SAW',
    'SAY', 'SEA', 'SET', 'SEW', 'SHE', 'SHY', 'SIN', 'SIP', 'SIR', 'SIS',
    'SIT', 'SIX', 'SKI', 'SKY', 'SLY', 'SOB', 'SOD', 'SON', 'SOP', 'SOT',
    'SOW', 'SOY', 'SPA', 'SPY', 'STY', 'SUB', 'SUM', 'SUN', 'SUP', 'TAB',
    'TAD', 'TAG', 'TAN', 'TAP', 'TAR', 'TAX', 'TEA', 'TED', 'TEE', 'TEN',
    'THE', 'TIE', 'TIN', 'TIP', 'TOE', 'TON', 'TOO', 'TOP', 'TOT', 'TOW',
    'TOY', 'TRY', 'TUB', 'TUG', 'TWO', 'URN', 'USE', 'VAN', 'VAT', 'VET',
    'VIA', 'VIE', 'VOW', 'WAD', 'WAG', 'WAR', 'WAS', 'WAX', 'WAY', 'WEB',
    'WED', 'WET', 'WHO', 'WIG', 'WIN', 'WIT', 'WOE', 'WOK', 'WON', 'WOO',
    'WOW', 'WRY', 'YAK', 'YAM', 'YAP', 'YAW', 'YEA', 'YES', 'YET', 'YEW',
    'YOU', 'ZAP', 'ZED', 'ZEN', 'ZIP', 'ZIT', 'ZOO',
    'ABLE', 'AGED', 'AIDE', 'AIMS', 'AIRY', 'AKIN', 'ALLY', 'ALSO', 'AMID',
    'ANTE', 'ARCH', 'AREA', 'ARID', 'ARMS', 'ARMY', 'ARTS', 'AUNT', 'AVID',
    'BAKE', 'BALD', 'BALE', 'BALL', 'BALM', 'BAND', 'BANE', 'BANG', 'BANK',
    'BARB', 'BARD', 'BARE', 'BARK', 'BARN', 'BASE', 'BATH', 'BEAD', 'BEAK',
    'BEAM', 'BEAN', 'BEAR', 'BEAT', 'BEEF', 'BELL', 'BELT', 'BEND', 'BEST',
    'BIKE', 'BILE', 'BILL', 'BIND', 'BIRD', 'BITE', 'BLAH', 'BLEW', 'BLOB',
    'BLOG', 'BLOT', 'BLUE', 'BOAR', 'BOAT', 'BODY', 'BOIL', 'BOLD', 'BOLT',
    'BOND', 'BONE', 'BOOK', 'BOOM', 'BOON', 'BOOT', 'BORE', 'BORN', 'BOSS',
    'BOTH', 'BOWL', 'BRAG', 'BRAN', 'BREW', 'BRIE', 'BRIM', 'BUCK', 'BULK',
    'BULL', 'BUMP', 'BURN', 'BURY', 'BUSH', 'BUSY', 'CAFE', 'CAGE', 'CAKE',
    'CALF', 'CALL', 'CALM', 'CAME', 'CAMP', 'CAPE', 'CARD', 'CARE', 'CARL',
    'CART', 'CASE', 'CASH', 'CAST', 'CAVE', 'CEDE', 'CHEW', 'CHIN', 'CHIP',
    'CHOP', 'CITY', 'CLAD', 'CLAM', 'CLAN', 'CLAP', 'CLAW', 'CLAY', 'CLEF',
    'CLIP', 'CLOG', 'CLUB', 'CLUE', 'COAL', 'COAT', 'COCK', 'CODE', 'COIN',
    'COLD', 'CONE', 'COOK', 'COOL', 'COPE', 'COPY', 'CORD', 'CORE', 'CORK',
    'CORN', 'COST', 'COZY', 'CRAB', 'CREW', 'CRIB', 'CROP', 'CROW', 'CUBE',
    'CURE', 'CURL', 'DARE', 'DARK', 'DARN', 'DART', 'DASH', 'DATA', 'DATE',
    'DAWN', 'DEAD', 'DEAF', 'DEAL', 'DEAR', 'DEBT', 'DECK', 'DEED', 'DEEM',
    'DEEP', 'DEER', 'DELI', 'DELL', 'DEMO', 'DENT', 'DESK', 'DIAL', 'DICE',
    'DIET', 'DIRT', 'DISH', 'DISK', 'DIVE', 'DOCK', 'DOES', 'DOLL', 'DOME',
    'DONE', 'DOOM', 'DOOR', 'DOSE', 'DOWN', 'DOZE', 'DRAB', 'DRAG', 'DRAW',
    'DREW', 'DRIP', 'DROP', 'DRUG', 'DRUM', 'DUAL', 'DUCK', 'DUCT', 'DUDE',
    'DUEL', 'DUET', 'DULL', 'DUMB', 'DUMP', 'DUNE', 'DUSK', 'DUST', 'DUTY',
    'EACH', 'EARL', 'EARN', 'EASE', 'EAST', 'EASY', 'EATS', 'EDGE', 'EDIT',
    'ELSE', 'EMIT', 'ENVY', 'EPIC', 'EVEN', 'EVER', 'EVIL', 'EXAM', 'EXEC',
    'EXIT', 'FACE', 'FACT', 'FADE', 'FAIL', 'FAIR', 'FAKE', 'FALL', 'FAME',
    'FANG', 'FARM', 'FAST', 'FATE', 'FAWN', 'FEAR', 'FEAT', 'FEED', 'FEEL',
    'FEET', 'FELL', 'FELT', 'FERN', 'FEUD', 'FILE', 'FILL', 'FILM', 'FIND',
    'FINE', 'FINK', 'FIRE', 'FIRM', 'FISH', 'FIST', 'FIVE', 'FLAG', 'FLAM',
    'FLAP', 'FLAT', 'FLAW', 'FLEA', 'FLED', 'FLEW', 'FLIP', 'FLOW', 'FLUE',
    'FOAL', 'FOAM', 'FOLD', 'FOLK', 'FOND', 'FONT', 'FOOD', 'FOOL', 'FOOT',
    'FORD', 'FORE', 'FORK', 'FORM', 'FORT', 'FOUL', 'FOUR', 'FREE', 'FROG',
    'FROM', 'FUEL', 'FULL', 'FUME', 'FUND', 'FUNK', 'FURY', 'FUSE', 'FUSS',
    'GAIT', 'GALE', 'GAME', 'GANG', 'GAPE', 'GASH', 'GATE', 'GAVE', 'GAZE',
    'GEAR', 'GELD', 'GEMS', 'GIFT', 'GILD', 'GILL', 'GILT', 'GIRL', 'GIST',
    'GIVE', 'GLAD', 'GLEE', 'GLEN', 'GLOW', 'GLUE', 'GLUM', 'GOAT', 'GOLD',
    'GOLF', 'GONE', 'GOOD', 'GORE', 'GOWN', 'GRAB', 'GRAM', 'GRAY', 'GREW',
    'GREY', 'GRID', 'GRIM', 'GRIN', 'GRIP', 'GROW', 'GRUB', 'GULF', 'GULL',
    'GUST', 'HACK', 'HAIR', 'HALE', 'HALF', 'HALL', 'HALT', 'HAND', 'HANG',
    'HARD', 'HARE', 'HARK', 'HARM', 'HARP', 'HASH', 'HAST', 'HATE', 'HATH',
    'HAUL', 'HAVE', 'HAZE', 'HAZY', 'HEAD', 'HEAL', 'HEAP', 'HEAR', 'HEAT',
    'HEEL', 'HEIR', 'HELL', 'HELM', 'HELP', 'HEMP', 'HERB', 'HERD', 'HERE',
    'HERO', 'HEWN', 'HICK', 'HIDE', 'HIGH', 'HIKE', 'HILL', 'HINT', 'HIRE',
    'HISS', 'HIVE', 'HOAX', 'HOCK', 'HOLD', 'HOLE', 'HOLY', 'HOME', 'HONE',
    'HONK', 'HOOD', 'HOOF', 'HOOK', 'HOOP', 'HOPE', 'HORN', 'HOSE', 'HOST',
    'HOUR', 'HOVE', 'HOWL', 'HUFF', 'HUGE', 'HULL', 'HUMP', 'HUNG', 'HUNK',
    'HUNT', 'HURL', 'HURT', 'HUSH', 'HYMN', 'IAMB', 'ICON', 'IDEA', 'IDLE',
    'IDOL', 'INCH', 'INTO', 'IRON', 'ISLE', 'ITEM', 'JACK', 'JADE', 'JAIL',
    'JAMB', 'JAZZ', 'JEAN', 'JEER', 'JELT', 'JERK', 'JEST', 'JIBE', 'JIFF',
    'JILT', 'JINX', 'JIVE', 'JOBS', 'JOCK', 'JOGS', 'JOLT', 'JOSH', 'JOUR',
    'JOWL', 'JUDO', 'JUGS', 'JUMP', 'JUNE', 'JUNK', 'JURY', 'JUST', 'JUTE',
    'KALE', 'KEEN', 'KEEP', 'KEGS', 'KELP', 'KENO', 'KEPT', 'KERF', 'KERN',
    'KEVL', 'KEYS', 'KICK', 'KIDS', 'KILL', 'KILN', 'KILO', 'KILT', 'KIND',
    'KING', 'KINK', 'KIPS', 'KISS', 'KITE', 'KIWI', 'KNEE', 'KNEW', 'KNIT',
    'KNOB', 'KNOT', 'KNOW', 'LABS', 'LACE', 'LACK', 'LACY', 'LAID', 'LAIR',
    'LAKE', 'LAMB', 'LAME', 'LAMP', 'LAND', 'LANE', 'LANK', 'LAST', 'LATE',
    'LAVA', 'LAWN', 'LAZY', 'LEAD', 'LEAF', 'LEAN', 'LEAP', 'LEFT', 'LEND',
    'LENS', 'LENT', 'LESS', 'LICK', 'LIDS', 'LIED', 'LIEN', 'LIFE', 'LIFT',
    'LIKE', 'LIMB', 'LIME', 'LIMP', 'LINE', 'LINK', 'LINT', 'LION', 'LIST',
    'LOAD', 'LOAF', 'LOCK', 'LOFT', 'LOGO', 'LONE', 'LONG', 'LOOK', 'LOOM',
    'LOOP', 'LOOT', 'LORD', 'LORE', 'LOSE', 'LOSS', 'LOST', 'LOUD', 'LOVE',
    'LUCK', 'LUMP', 'LUNG', 'LURE', 'LURK', 'LUSH', 'LUST', 'MACE', 'MADE',
    'MAID', 'MAIL', 'MAIN', 'MAKE', 'MALE', 'MALL', 'MALT', 'MANE', 'MANY',
    'MARK', 'MARS', 'MART', 'MASK', 'MASS', 'MAST', 'MATE', 'MAZE', 'MEAD',
    'MEAL', 'MEAN', 'MEAT', 'MEEK', 'MEET', 'MELD', 'MELT', 'MEMO', 'MEND',
    'MENU', 'MERE', 'MESH', 'MESS', 'MICE', 'MILD', 'MILK', 'MILL', 'MIME',
    'MIND', 'MINE', 'MINI', 'MINK', 'MINT', 'MINX', 'MIRE', 'MISS', 'MIST',
    'MITE', 'MITT', 'MOAN', 'MOAT', 'MOCK', 'MODE', 'MOLD', 'MOLE', 'MOLT',
    'MONK', 'MOOD', 'MOON', 'MOOR', 'MOOT', 'MORE', 'MORN', 'MOSS', 'MOST',
    'MOTH', 'MOVE', 'MUCH', 'MUCK', 'MUFF', 'MULE', 'MULL', 'MURK', 'MUSE',
    'MUSH', 'MUST', 'MUTE', 'MYTH', 'NAIL', 'NAME', 'NAPE', 'NARY', 'NAVE',
    'NEAR', 'NEAT', 'NECK', 'NEED', 'NEON', 'NEST', 'NEWS', 'NEWT', 'NEXT',
    'NICE', 'NICK', 'NILE', 'NINE', 'NODE', 'NONE', 'NOOK', 'NOON', 'NORM',
    'NOSE', 'NOTE', 'NOUN', 'NUMB', 'OAKS', 'OARS', 'OATH', 'OBEY', 'ODDS',
    'ODOR', 'OGLE', 'OGRE', 'OMEN', 'OMIT', 'ONCE', 'ONLY', 'ONTO', 'ONUS',
    'OOZE', 'OPAL', 'OPEN', 'OPUS', 'ORAL', 'ORBS', 'ORGY', 'OVEN', 'OVER',
    'OWED', 'OWES', 'OWLS', 'OYES', 'PACE', 'PACK', 'PACT', 'PAGE', 'PAID',
    'PAIL', 'PAIN', 'PAIR', 'PALE', 'PALM', 'PALS', 'PANG', 'PANS', 'PANT',
    'PAPA', 'PARA', 'PARD', 'PARE', 'PARK', 'PART', 'PASS', 'PAST', 'PATH',
    'PATS', 'PAVE', 'PAWN', 'PEAK', 'PEAL', 'PEAR', 'PEAT', 'PECK', 'PEEL',
    'PEEP', 'PEER', 'PELT', 'PEND', 'PENS', 'PENT', 'PEON', 'PERK',
    'PERM', 'PERP', 'PEST', 'PETS', 'PEWS', 'PICK', 'PIER', 'PIGS', 'PIKE',
    'PILE', 'PILL', 'PINE', 'PING', 'PINK', 'PINS', 'PINT', 'PIPE', 'PITA',
    'PITH', 'PITS', 'PITY', 'PLAN', 'PLAY', 'PLEA', 'PLED', 'PLOD', 'PLOP',
    'PLOT', 'PLOW', 'PLUG', 'PLUM', 'PLUS', 'POKE', 'POLL', 'POLO', 'POND',
    'PONG', 'PONY', 'POOL', 'POOR', 'POPE', 'PORK', 'PORT', 'POSE', 'POSH',
    'POST', 'POSY', 'POTS', 'POUR', 'PRAY', 'PREP', 'PREY', 'PRIG', 'PRIM',
    'PROD', 'PROF', 'PROM', 'PROP', 'PROS', 'PROW', 'PSIS', 'PULP', 'PUMP',
    'PUNK', 'PUNS', 'PUNT', 'PUNY', 'PUPA', 'PUPS', 'PURE', 'PURL', 'PURR',
    'PUSH', 'PUTS', 'PUTT', 'QUAD', 'QUAG', 'QUID', 'QUIN', 'QUIP', 'QUIT',
    'QUIZ', 'RACE', 'RACK', 'RAFT', 'RAGE', 'RAID', 'RAIL', 'RAIN', 'RAKE',
    'RAMP', 'RANG', 'RANK', 'RANT', 'RARE', 'RASH', 'RASP', 'RATE', 'RAVE',
    'READ', 'REAL', 'REAM', 'REAP', 'REAR', 'REED', 'REEF', 'REIN', 'REND',
    'RENT', 'REST', 'RIBS', 'RICE', 'RICH', 'RICK', 'RIDE', 'RIDS', 'RIFT',
    'RIGS', 'RILE', 'RIME', 'RIMS', 'RIND', 'RING', 'RIOT', 'RIPE', 'RIPS',
    'RISE', 'RISK', 'RITE', 'RIVE', 'ROAD', 'ROAM', 'ROAR', 'ROBE', 'ROBS',
    'ROCK', 'RODE', 'ROLE', 'ROLL', 'ROMP', 'ROOD', 'ROOF', 'ROOM', 'ROOT',
    'ROPE', 'ROSE', 'ROSY', 'ROTS', 'ROUT', 'ROVE', 'ROWS', 'RUBE', 'RUBS',
    'RUBY', 'RUDE', 'RUED', 'RUES', 'RUFF', 'RUIN', 'RULE', 'RUMP', 'RUPE',
    'RUSE', 'RUSH', 'RUST', 'SACK', 'SAFE', 'SAGE', 'SAID', 'SAIL', 'SAKE',
    'SALE', 'SALT', 'SAME', 'SAND', 'SANE', 'SANG', 'SANK', 'SASH', 'SAVE',
    'SEAL', 'SEAM', 'SEAR', 'SEAT', 'SECT', 'SEED', 'SEEK', 'SEEM', 'SEEN',
    'SEEP', 'SEER', 'SELF', 'SELL', 'SEND', 'SENT', 'SEPT', 'SERF', 'SETS',
    'SHED', 'SHIN', 'SHIP', 'SHOE', 'SHOP', 'SHOT', 'SHOW', 'SHUN', 'SHUT',
    'SICK', 'SIDE', 'SIFT', 'SIGH', 'SIGN', 'SILK', 'SILL', 'SILO', 'SILT',
    'SINE', 'SING', 'SINK', 'SIRE', 'SITE', 'SITS', 'SIZE', 'SKEW', 'SKID',
    'SKIM', 'SKIN', 'SKIP', 'SLAB', 'SLAM', 'SLAP', 'SLAT', 'SLED', 'SLEW',
    'SLID', 'SLIM', 'SLIT', 'SLOB', 'SLOP', 'SLOT', 'SLOW', 'SLUG', 'SLUM',
    'SMOG', 'SNAG', 'SNAP', 'SNIP', 'SNOB', 'SNOW', 'SNUB', 'SNUG', 'SOAK',
    'SOAP', 'SOAR', 'SOCK', 'SODA', 'SOFA', 'SOFT', 'SOIL', 'SOLD', 'SOLE',
    'SOME', 'SONG', 'SOON', 'SOOT', 'SORE', 'SORT', 'SOUL', 'SOUP', 'SOUR',
    'SOWN', 'SPAN', 'SPAR', 'SPEC', 'SPED', 'SPEW', 'SPIN', 'SPIT', 'SPOT',
    'SPRY', 'SPUN', 'SPUR', 'STAB', 'STAG', 'STAR', 'STAY', 'STEM', 'STEP',
    'STEW', 'STIR', 'STOP', 'STOW', 'STUB', 'STUD', 'STUN', 'STYE', 'SUBS',
    'SUCH', 'SUDS', 'SUIT', 'SULK', 'SUMO', 'SUMP', 'SUMS', 'SUNG', 'SUNK',
    'SUNS', 'SUPS', 'SURE', 'SURF', 'SWAB', 'SWAG', 'SWAM', 'SWAN', 'SWAP',
    'SWAT', 'SWAY', 'SWIG', 'SWIM', 'SWUM', 'TACK', 'TACT', 'TAGS', 'TAIL',
    'TAKE', 'TALC', 'TALE', 'TALK', 'TALL', 'TAME', 'TANG', 'TANK', 'TANS',
    'TAPE', 'TAPS', 'TARN', 'TARO', 'TARP', 'TART', 'TASK', 'TAUT', 'TEAK',
    'TEAL', 'TEAM', 'TEAR', 'TEAS', 'TELL', 'TEMP', 'TEND', 'TENT', 'TERM',
    'TEST', 'TEXT', 'THAN', 'THAT', 'THEM', 'THEN', 'THEY', 'THIN', 'THIS',
    'THUD', 'THUG', 'TICK', 'TIDE', 'TIDY', 'TIED', 'TIER', 'TIES', 'TIFF',
    'TILE', 'TILL', 'TILT', 'TIME', 'TINS', 'TINT', 'TINY', 'TIRE', 'TOAD',
    'TOGA', 'TOIL', 'TOLD', 'TOLL', 'TOMB', 'TOME', 'TONE', 'TOOK', 'TOOL',
    'TOOT', 'TOPS', 'TORE', 'TORN', 'TOSS', 'TOUR', 'TOUT', 'TOWN', 'TRAM',
    'TRAP', 'TRAY', 'TREE', 'TREK', 'TRIM', 'TRIO', 'TRIP', 'TROD', 'TROT',
    'TRUE', 'TUBA', 'TUBE', 'TUBS', 'TUCK', 'TUFT', 'TUGS', 'TUNA', 'TUNE',
    'TURF', 'TURN', 'TUSK', 'TWIG', 'TWIN', 'TYPE', 'TYPO', 'UGLY',
    'UNDO', 'UNIT', 'UNTO', 'UPON', 'URGE', 'USED', 'USER', 'VAST', 'VEIL',
    'VEIN', 'VENT', 'VERB', 'VERY', 'VEST', 'VETO', 'VICE', 'VINE', 'VISA',
    'VISE', 'VOID', 'VOLT', 'VOTE', 'WADE', 'WAGE', 'WAIL', 'WAIT', 'WAKE',
    'WALE', 'WALK', 'WALL', 'WAND', 'WANT', 'WARD', 'WARM', 'WARN', 'WARP',
    'WARS', 'WART', 'WARY', 'WASH', 'WASP', 'WAVE', 'WAVY', 'WEAK', 'WEAR',
    'WEED', 'WEEK', 'WEEP', 'WELD', 'WELL', 'WENT', 'WEPT', 'WEST', 'WHIP',
    'WHIR', 'WICK', 'WIDE', 'WIFE', 'WILD', 'WILL', 'WILT', 'WIND', 'WINE',
    'WING', 'WINK', 'WINS', 'WIPE', 'WIRE', 'WISE', 'WISH', 'WISP', 'WITH',
    'WITS', 'WOKE', 'WOKS', 'WOLD', 'WOLF', 'WOMB', 'WOOD', 'WOOF', 'WOOL',
    'WORD', 'WORE', 'WORK', 'WORM', 'WORN', 'WRAP', 'WRIT', 'YARD', 'YARN',
    'YAWN', 'YEAH', 'YEAR', 'YELL', 'YELP', 'YOKE', 'YORE', 'YOUR', 'YULE',
    'ZEAL', 'ZERO', 'ZEST', 'ZINC', 'ZONE',
  };

  // ─── State ────────────────────────────────────────────────────────
  late List<String> _board; // 12 letters
  late Set<String> _validWords;

  // Words the player has already locked in this round.
  final List<String> _foundWords = [];

  // Indices (into _board) of currently selected tiles in order.
  final List<int> _path = [];

  int _score = 0;
  int _coins = 10;

  String? _statusMessage; // transient feedback ("Nice!", "Not a word")
  Timer? _statusTimer;

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _setupRound();
    _ready = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      reportScore(_score);
      reportStats('${_foundWords.length} words · ${_validWords.length} possible');
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _setupRound() {
    final rng = widget.dailyChallenge
        ? Random(dailySeedFor('word-master'))
        : Random();

    // Letters with higher English frequency get more weight so the
    // generated boards are more likely to contain real words.
    const freq = <String, int>{
      'A': 9, 'B': 2, 'C': 3, 'D': 4, 'E': 12, 'F': 2, 'G': 3, 'H': 2,
      'I': 9, 'J': 1, 'K': 1, 'L': 4, 'M': 3, 'N': 6, 'O': 8, 'P': 3,
      'Q': 1, 'R': 6, 'S': 6, 'T': 6, 'U': 4, 'V': 2, 'W': 2, 'X': 1,
      'Y': 2, 'Z': 1,
    };
    final freqEntries = freq.entries.toList(growable: false);
    final totalFreq =
        freqEntries.fold<int>(0, (s, e) => s + e.value);

    List<String> pickWeighted(int n) {
      return List<String>.generate(n, (_) {
        var r = rng.nextInt(totalFreq);
        for (final e in freqEntries) {
          r -= e.value;
          if (r < 0) return e.key;
        }
        return freqEntries.last.key;
      });
    }

    bool canBuild(String word, Map<String, int> counts) {
      final seen = <String, int>{};
      for (final c in word.split('')) {
        final n = (seen[c] ?? 0) + 1;
        seen[c] = n;
        if ((counts[c] ?? 0) < n) return false;
      }
      return true;
    }

    // Try up to 60 random boards and pick the first that produces
    // 8+ valid words from the embedded dictionary.
    for (var attempt = 0; attempt < 60; attempt++) {
      final pick = pickWeighted(12);
      final counts = <String, int>{};
      for (final l in pick) {
        counts[l] = (counts[l] ?? 0) + 1;
      }
      final valid = <String>{};
      for (final w in _dictionary) {
        if (canBuild(w, counts)) valid.add(w);
      }
      if (valid.length >= 8) {
        _board = pick;
        _validWords = valid;
        return;
      }
    }
    // Fallback — guaranteed to produce several words. E/A/L/T are the
    // most common English letters so this board always finds matches.
    _board = const ['A', 'B', 'C', 'E', 'L', 'A', 'N', 'D', 'E', 'R', 'S', 'T'];
    final counts = <String, int>{};
    for (final l in _board) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
    final valid = <String>{};
    for (final w in _dictionary) {
      if (canBuild(w, counts)) valid.add(w);
    }
    _validWords = valid;
  }

  // ─── Actions ──────────────────────────────────────────────────────

  void _onTileTap(int idx) {
    if (idx < 0 || idx >= _board.length) return;
    if (_path.isNotEmpty && _path.last == idx) {
      _submit();
      return;
    }
    if (_path.contains(idx)) {
      setState(() {
        _path.removeRange(_path.indexOf(idx) + 1, _path.length);
      });
      haptic(HapticFeedbackType.light);
      return;
    }
    setState(() {
      _path.add(idx);
    });
    haptic(HapticFeedbackType.selection);
  }

  void _submit() {
    final word = _path.map((i) => _board[i]).join();
    if (word.length < 3) {
      _flash('Need 3+ letters', isError: true);
      _clearPath();
      return;
    }
    if (_foundWords.contains(word)) {
      _flash('Already found', isError: true);
      _clearPath();
      return;
    }
    if (!_validWords.contains(word)) {
      _flash('Not a word', isError: true);
      _clearPath();
      return;
    }
    setState(() {
      _foundWords.add(word);
      _score += word.length * 10;
      _coins += 1;
    });
    haptic(HapticFeedbackType.medium);
    _clearPath();
    _flash('Nice!');
    reportScore(_score);
    reportStats('${_foundWords.length} words · ${_validWords.length} possible');
  }

  void _clearPath() {
    if (_path.isEmpty) return;
    setState(() => _path.clear());
  }

  void _shuffle() {
    if (_board.length < 2) return;
    setState(() {
      _board = List<String>.from(_board)..shuffle(Random());
      _path.clear();
    });
    haptic(HapticFeedbackType.selection);
  }

  void _hint() {
    if (_coins <= 0) {
      _flash('Out of hints', isError: true);
      return;
    }
    final remaining = _validWords
        .where((w) => !_foundWords.contains(w))
        .toList();
    if (remaining.isEmpty) {
      _flash('All words found!', isError: false);
      return;
    }
    final pick = remaining[Random().nextInt(remaining.length)];
    setState(() {
      _coins -= 1;
    });
    _flash('Hint: $pick', isError: false);
    haptic(HapticFeedbackType.medium);
  }

  void _flash(String msg,
      {bool isError = false, Duration duration = const Duration(seconds: 1)}) {
    _statusTimer?.cancel();
    setState(() => _statusMessage = msg);
    _statusTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() => _statusMessage = null);
    });
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      color: const Color(0xFF0B1226),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Stats chip row — replaces the old hardcoded score row.
              _StatsRow(
                score: _score,
                found: _foundWords.length,
                possible: _validWords.length,
                coins: _coins,
              ),
              const SizedBox(height: 16),
              // Main 4×3 letter board.
              Expanded(
                flex: 5,
                child: _BigBoard(
                  board: _board,
                  path: _path,
                  onTap: _onTileTap,
                ),
              ),
              const SizedBox(height: 12),
              // Current selection + found-words strip + status.
              _SelectionStrip(
                selection: _path.map((i) => _board[i]).join(),
                foundWords: _foundWords,
                statusMessage: _statusMessage,
              ),
              const SizedBox(height: 12),
              // Bottom action row — Shuffle / Hint / Submit.
              Row(
                children: [
                  _ShuffleButton(onTap: _shuffle),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _HintButton(
                      coins: _coins,
                      onTap: _hint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _SubmitButton(
                      onTap: _submit,
                      disabled: _path.isEmpty,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Footer hint line — uses theme color so it adapts to
              // light/dark mode automatically.
              Text(
                _path.isEmpty
                    ? 'Tap letters to build a word'
                    : 'Tap Submit to lock in · tap a tile to backtrack',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Stats row — score / words found / coins / target — pure data, no
// decoration, no scene clutter.
// ────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.score,
    required this.found,
    required this.possible,
    required this.coins,
  });

  final int score;
  final int found;
  final int possible;
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            label: 'Score',
            value: '$score',
            color: const Color(0xFF22C55E),
            icon: Icons.star_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'Words',
            value: '$found / $possible',
            color: const Color(0xFF1E90FF),
            icon: Icons.text_fields_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'Coins',
            value: '$coins',
            color: const Color(0xFFFACC15),
            icon: Icons.bolt_rounded,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF102042),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFB8C2E0),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// 4×3 wooden letter board (the main puzzle surface).
// ────────────────────────────────────────────────────────────────────

class _BigBoard extends StatelessWidget {
  const _BigBoard({
    required this.board,
    required this.path,
    required this.onTap,
  });

  final List<String> board;
  final List<int> path;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      const cols = 4;
      const rows = 3;
      const gap = 8.0;
      final cellW = (c.maxWidth - gap * (cols - 1)) / cols;
      final cellH = (c.maxHeight - gap * (rows - 1)) / rows;
      final cell = cellW < cellH ? cellW : cellH;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List.generate(board.length, (i) {
          final selected = path.contains(i);
          final isLast = path.isNotEmpty && path.last == i;
          return GestureDetector(
            onTap: () => onTap(i),
            child: SizedBox(
              width: cell,
              height: cell,
              child: _WoodTile(
                letter: board[i],
                selected: selected,
                lastInPath: isLast,
              ),
            ),
          );
        }),
      );
    });
  }
}

class _WoodTile extends StatelessWidget {
  const _WoodTile({
    required this.letter,
    required this.selected,
    required this.lastInPath,
  });

  final String letter;
  final bool selected;
  final bool lastInPath;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? const Color(0xFF22C55E)
        : const Color(0xFF8B5A2B);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5E6C5), Color(0xFFD9A968)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: selected ? 3 : 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: selected ? 14 : 6,
            offset: Offset(0, selected ? 4 : 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 32,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Selection strip — shows the word being built, found-words, status.
// ────────────────────────────────────────────────────────────────────

class _SelectionStrip extends StatelessWidget {
  const _SelectionStrip({
    required this.selection,
    required this.foundWords,
    required this.statusMessage,
  });

  final String selection;
  final List<String> foundWords;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF102042),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2B3A66)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: caption + status.
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Build a word from the letters',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (statusMessage != null)
                Text(
                  statusMessage!,
                  style: TextStyle(
                    color: statusMessage == 'Nice!'
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFFF5571),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: foundWords.length + (selection.isEmpty ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                if (i < foundWords.length) {
                  return _WordSlot(label: foundWords[i], found: true);
                }
                return _WordSlot(label: selection, found: false);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WordSlot extends StatelessWidget {
  const _WordSlot({required this.label, required this.found});
  final String label;
  final bool found;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: found ? const Color(0xFF22C55E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: found ? Colors.white : const Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          if (found) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Action buttons — Shuffle / Hint / Submit.
// ────────────────────────────────────────────────────────────────────

class _ShuffleButton extends StatelessWidget {
  const _ShuffleButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: const Color(0xFF1F2A4A),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: const Center(
            child: Icon(Icons.shuffle_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _HintButton extends StatelessWidget {
  const _HintButton({required this.coins, required this.onTap});
  final int coins;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = coins <= 0;
    return SizedBox(
      height: 54,
      child: Material(
        color: disabled
            ? const Color(0xFF1F2A4A)
            : const Color(0xFF1E90FF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              const Text(
                'Hint',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFACC15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        color: Color(0xFF111827), size: 12),
                    const SizedBox(width: 2),
                    Text(
                      '$coins',
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.onTap, required this.disabled});
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: disabled
            ? const Color(0xFFCA8A04).withValues(alpha: 0.45)
            : const Color(0xFFFACC15),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : onTap,
          child: const Center(
            child: Text(
              'Submit',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
