import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import '../../core/repository.dart';

Future<Repository> openAppRepository() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return Repository.open(databaseFactoryIo, p.join(dir.path, 'recall.db'));
}
