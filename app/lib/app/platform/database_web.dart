import 'package:sembast_web/sembast_web.dart';

import '../../core/repository.dart';

Future<Repository> openAppRepository() =>
    Repository.open(databaseFactoryWeb, 'recall-flutter');
