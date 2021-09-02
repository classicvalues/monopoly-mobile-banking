import 'dart:developer';
import 'dart:math' hide log;

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:deep_pick/deep_pick.dart';
import 'package:user_repository/user_repository.dart';

import 'models/models.dart';

enum CreateNewGameResult { none, success, noConnection, failure }

enum JoinGameResult {
  none,
  success,
  noConnection,
  gameNotFound,
  tooManyPlayers,
  failure
}

class BankingRepository {
  const BankingRepository({required this.userRepository});
  final UserRepository userRepository;

  // #### Firebase Collection references:
  static CollectionReference<Game> get _gamesCollection =>
      FirebaseFirestore.instance.collection('games').withConverter<Game>(
            fromFirestore: (snap, _) => Game.fromSnapshot(snap),
            toFirestore: (model, _) => model.toDocument(),
          );

  // #### Public methods:

  /// Streams the game with the given id.
  Stream<Game?> streamGame(String currentGameId) {
    return _gamesCollection
        .doc(currentGameId)
        .snapshots(includeMetadataChanges: true)
        .map((doc) => doc.data());
  }

  /// Disconnects from any game.
  Future<void> leaveGame() async {
    await userRepository.setCurrentGameId(null);
  }

  Future<JoinGameResult> joinGame(String gameId) async {
    gameId = gameId.toUpperCase();

    try {
      final gameSnapshot = await _gamesCollection.doc(gameId).get();

      if (!gameSnapshot.exists) return JoinGameResult.gameNotFound;

      final game = gameSnapshot.data()!;

      final wasAlreadyConnectedToGame = game.players
          .asList()
          .where((player) => player.userId == userRepository.user.id)
          .isNotEmpty;

      if (game.players.size >= 6 && !wasAlreadyConnectedToGame) {
        return JoinGameResult.tooManyPlayers;
      }

      // Join the game:
      final updatedGame = game.addPlayer(userRepository.user);
      await _gamesCollection.doc(game.id).set(updatedGame);
      await userRepository.setCurrentGameId(game.id);

      return JoinGameResult.success;
    } on FirebaseException catch (e) {
      log('FirebaseException in joinGame(): $e');

      switch (e.code) {
        case 'unavailable':
          return JoinGameResult.noConnection;
        default:
          return JoinGameResult.failure;
      }
    } catch (e) {
      log('Unknown exception in joinGame(): $e');

      return JoinGameResult.failure;
    }
  }

  /// Creates a new game lobby and returns itself.
  Future<CreateNewGameResult> createNewGameAndJoin({
    required int startingCapital,
    required int salary,
    required bool enableFreeParkingMoney,
  }) async {
    try {
      final gameId = await _uniqueGameId();

      assert(!(await _gamesCollection.doc(gameId).get()).exists);

      await _gamesCollection.doc(gameId).set(
            Game.newOne(
              id: _randomGameId(),
              startingCapital: startingCapital,
              salary: salary,
              enableFreeParkingMoney: enableFreeParkingMoney,
            ),
          );

      final game = (await _gamesCollection.doc(gameId).get()).data()!;

      // Join the game:
      final updatedGame = game.addPlayer(userRepository.user);
      await _gamesCollection.doc(game.id).set(updatedGame);
      await userRepository.setCurrentGameId(game.id);

      return CreateNewGameResult.success;
    } on FirebaseException catch (e) {
      log('FirebaseException in createNewGameAndJoin(): $e');

      switch (e.code) {
        case 'unavailable':
          return CreateNewGameResult.noConnection;
        default:
          return CreateNewGameResult.failure;
      }
    } catch (e) {
      log('Unknown exception in createNewGameAndJoin(): $e');

      return CreateNewGameResult.failure;
    }
  }

  /// Gets a random game id until it is unique.
  // todo: avoid waiting forever when all ids are taken.
  Future<String> _uniqueGameId() async {
    final id = _randomGameId();

    while ((await _gamesCollection.doc(id).get()).exists) {
      return _uniqueGameId();
    }

    return id;
  }

  /// Generates a random game id.
  String _randomGameId() {
    const length = 4;
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

    return List.generate(
      length,
      (index) => chars[Random.secure().nextInt(chars.length)],
    ).join('');
  }

  /// Transfers money from one player to another.
  ///
  /// Use custom constructors for the transaction object:
  /// For example Transaction.fromBank(...) or Transaction.toPlayer(...).
  Future<void> makeTransaction({
    required Game game,
    required Transaction transaction,
  }) async {
    final updatedGame = game.makeTransaction(transaction);

    //todo: update timestamp to server timestamp!
    await _gamesCollection.doc(game.id).set(updatedGame);

    // Check if game has a winner after the transaction:
    if (updatedGame.winner != null) {
      await _incrementWinsOfUser(updatedGame.winner!.userId);
    }
  }

  /// Increments the win field of a user in firestore.
  Future<void> _incrementWinsOfUser(String userId) async {
    await userRepository.usersCollection
        .doc(userId)
        .update({'wins': FieldValue.increment(1)});
  }
}

extension TimestampPick on Pick {
  Timestamp asFirestoreTimeStampOrThrow() {
    final value = required().value;
    if (value is Timestamp) {
      return value;
    }
    if (value is int) {
      return Timestamp.fromMillisecondsSinceEpoch(value);
    }
    throw PickException(
        "value $value at $debugParsingExit can't be casted to Timestamp");
  }

  Timestamp? asFirestoreTimeStampOrNull() {
    if (value == null) return null;
    try {
      return asFirestoreTimeStampOrThrow();
    } catch (_) {
      return null;
    }
  }
}
