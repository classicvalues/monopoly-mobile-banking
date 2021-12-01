import 'dart:developer';

import 'package:banking_repository/banking_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:routemaster/routemaster.dart';
import 'package:user_repository/user_repository.dart';

import 'app.dart';
import 'authentication/cubit/auth_cubit.dart';

bool kUseFirebaseEmulator = kDebugMode;

void main() async {
  Routemaster.setPathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Make background of gesture navigation bar transparent:
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  final userRepository = UserRepository(
    useFirebaseEmulator: kUseFirebaseEmulator,
  );
  await userRepository.getOpeningUser();

  BlocOverrides.runZoned(
    () => runApp(_Providers(userRepository: userRepository)),
    blocObserver: kDebugMode ? _AppBlocObserver() : null,
  );
}

class _Providers extends StatelessWidget {
  const _Providers({Key? key, required this.userRepository}) : super(key: key);
  final UserRepository userRepository;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (_) => userRepository,
      child: BlocProvider(
        create: (_) => AuthCubit(userRepository: userRepository),
        child: RepositoryProvider(
          create: (_) => BankingRepository(
            userRepository: userRepository,
            useFirebaseEmulator: kUseFirebaseEmulator,
          ),
          child: const App(),
        ),
      ),
    );
  }
}

class _AppBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}
