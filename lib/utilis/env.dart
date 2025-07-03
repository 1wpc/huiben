import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
    @EnviedField(varName: 'DOUBAO_APIKEY', obfuscate: true)
    static final String doubaoApiKey = _Env.doubaoApiKey;
}