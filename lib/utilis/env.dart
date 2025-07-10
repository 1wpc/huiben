import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
    @EnviedField(varName: 'DOUBAO_APIKEY', obfuscate: true)
    static final String doubaoApiKey = _Env.doubaoApiKey;
    
    @EnviedField(varName: 'XUNFEI_APP_ID', obfuscate: true)
    static final String xunfeiAppId = _Env.xunfeiAppId;
    
    @EnviedField(varName: 'XUNFEI_API_KEY', obfuscate: true)
    static final String xunfeiApiKey = _Env.xunfeiApiKey;
    
    @EnviedField(varName: 'XUNFEI_API_SECRET', obfuscate: true)
    static final String xunfeiApiSecret = _Env.xunfeiApiSecret;
}