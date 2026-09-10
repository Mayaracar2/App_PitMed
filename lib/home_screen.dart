import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterBlueClassic _bt = FlutterBlueClassic();

  // ── Bluetooth ──────────────────────────────────────────────
  BluetoothConnection? _connection;
  List<BluetoothDevice> _dispositivos = [];
  bool _btConectado = false;
  StreamSubscription<Uint8List>? _inputSub;

  // ── Speech ─────────────────────────────────────────────────
  final SpeechToText _speech1 = SpeechToText();
  final SpeechToText _speech2 = SpeechToText();
  bool _speechDisponivel = false;

  // ── Variáveis globais ──────────────────────────────────────
  String _ultimaLetraEnviada = '0';
  List<String> _letras = [];
  int _indexAtual = 0;
  String _letraCorreta = '0';
  bool _palavraCapturada = false;
  bool _estaOuvindo = false;
  String _mensagemRecebida = '';
  String _bufferBT = '';
  Timer? _speechTimeout;
  Timer? _trocaPalavraTimer;
  bool _aguardandoFeedback = false;
  String _letraReconhecida = '';
  bool _entradaEhFrase = false;

  // ── Labels ─────────────────────────────────────────────────
  String _label1 =
      'Conecte-se ao dispositivo bluetooth PitMed para enviar as mensagens ao Equipamento de comunicação.';
  String _label2 = '';
  String _label3 = '';
  String _label4 = '';
  String _label5 = 'Aqui aparecerá a letra para comparação';

  final TextEditingController _textController = TextEditingController();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _inicializar();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _speechTimeout?.cancel();
    _trocaPalavraTimer?.cancel();
    _inputSub?.cancel();
    _connection?.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    await _solicitarPermissoes();

    bool btAtivo = await _bt.isEnabled;
    if (!btAtivo) {
      setState(() => _label2 = 'Ative o Bluetooth do Celular');
    }

    bool ok = await _speech1.initialize();
    await _speech2.initialize(
      onStatus: _onSpeech2Status,
      onError: (error) {
        _finalizarEscutaComErro();
      },
    );
    setState(() => _speechDisponivel = ok);
  }

  Future<void> _solicitarPermissoes() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.microphone,
      Permission.location,
    ].request();
  }

  Future<void> _listarDispositivos() async {
    setState(() => _label2 = 'Dispositivos Listados');

    final devs = await _bt.bondedDevices;

    setState(() {
      _dispositivos = devs ?? [];
    });

    if (_dispositivos.isEmpty) {
      setState(() => _label2 = 'Nenhum dispositivo pareado encontrado');
      return;
    }
    _mostrarListaPicker();
  }

  void _mostrarListaPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selecione o dispositivo'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _dispositivos.length,
            itemBuilder: (_, i) {
              final dev = _dispositivos[i];
              return ListTile(
                title: Text(dev.name ?? 'Desconhecido'),
                subtitle: Text(dev.address),
                onTap: () {
                  Navigator.pop(ctx);
                  _conectar(dev);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          )
        ],
      ),
    );
  }

  //_______________Conexão Blluetooth ________________
  Future<void> _conectar(BluetoothDevice device) async {
    try {
      final conn = await _bt.connect(device.address);

      if (conn == null) {
        setState(() {
          _label2 = 'Falha ao conectar.';
        });
        return;
      }

      setState(() {
        _connection = conn;
        _btConectado = true;
        _label2 = 'Bluetooth conectado.';
      });

      _inputSub?.cancel();

      final input = conn.input;

      if (input != null) {
        _inputSub = input.listen((data) {
          _bufferBT += String.fromCharCodes(data);

          if (_bufferBT.contains('PRESS')) {
            _processarComandoBluetooth('PRESS');
            _bufferBT = '';
          } else if (_bufferBT.contains('RELEASE')) {
            _processarComandoBluetooth('RELEASE');
            _bufferBT = '';
          }
        });

        _inputSub!.onDone(() {
          setState(() {
            _btConectado = false;
            _label2 = 'Bluetooth desconectado.';
          });
        });
      }
    } catch (e) {
      setState(() {
        _label2 = 'Falha ao conectar: $e';
      });
    }
  }

  void _processarComandoBluetooth(String msg) {
    if (!_aguardandoFeedback) return;

    if (msg.contains('PRESS')) {
      _speech2GetText();
    }

    if (msg.contains('RELEASE')) {
      _speech2.stop();
    }
  }

  void _enviarBT(String texto) {
    if (_btConectado && _connection != null) {
      _connection!.output.add(Uint8List.fromList(texto.codeUnits));
    }
  }

  void _onBotaoEnviar() {
    //String resposta = _ultimaLetraEnviada.trim().toUpperCase();
    //String correta = _letraCorreta.trim().toUpperCase();

    setState(() {
      _label2 = _btConectado
          ? 'Mensagem Enviada'
          : 'Falha ao enviar a mensagem. Cheque sua conexão bluetooth.';
    });

    _enviarBT(_letraCorreta);
  }

  void _onBotaoFeedback() {
    if (!_speechDisponivel) return;
    _speech1.listen(
      onResult: (result) {
        if (result.finalResult) {
          setState(() {
            _textController.text = result.recognizedWords;
            _label2 = 'Conectado.';
          });
        }
      },
      localeId: 'pt_BR',
    );
  }

  void _speech2GetText() {
    if (!_speechDisponivel || _estaOuvindo) return;

    setState(() {
      _estaOuvindo = true;
      _letraReconhecida = ''; // limpa o resultado da rodada anterior
    });

    _speech2.listen(
      localeId: 'pt_BR',
      onResult: (result) {
        if (result.finalResult) {
          _speechTimeout?.cancel();
          _speech2AfterGettingText(result.recognizedWords);
        }
      },
    );

    _speechTimeout?.cancel();
    _speechTimeout = Timer(const Duration(seconds: 8), () {
      if (_estaOuvindo) {
        _finalizarEscutaComErro();
      }
    });
  }

  void _onSpeech2Status(String status) {
    if ((status == 'done' || status == 'notListening') && _estaOuvindo) {
      _finalizarEscutaComErro();
    }
  }

  void _finalizarEscutaComErro() {
    if (!_estaOuvindo) return;

    _speechTimeout?.cancel();
    _speech2.stop();

    setState(() {
      _estaOuvindo = false;
      _label4 = '(não reconhecido)';
      _letraReconhecida = '';
    });

    Vibration.vibrate(duration: 2000);
  }

  String _extrairLetra(String resultado) {
    String texto = resultado.trim().toUpperCase();

    // remove acentos comuns pra não perder "Á", "É" etc.
    const comAcento = 'ÁÀÂÃÉÈÊÍÌÎÓÒÔÕÚÙÛÇ';
    const semAcento = 'AAAAEEEIIIOOOOUUUC';
    for (int i = 0; i < comAcento.length; i++) {
      texto = texto.replaceAll(comAcento[i], semAcento[i]);
    }

    // remove a palavra "LETRA" se estiver presente
    texto = texto.replaceAll('LETRA', '').trim();

    // pega só o último "token" (última palavra/caractere falado)
    final partes =
        texto.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '';

    String ultima = partes.last;

    // se sobrou mais de 1 caractere (ex: "AGÁ" pro H), tenta mapear pelo nome fonético
    const mapaFonetico = {
      'AGA': 'H', 'AGÁ': 'H',
      'DABLIU': 'W', 'DOIS-V': 'W', 'DOISVES': 'W',
      'IPSILON': 'Y', 'ÍPSILON': 'Y',
      'ERRE': 'R', 'ESSE': 'S', 'EFE': 'F',
      'CÁ': 'K', 'CA': 'K',
      // adicione outras conforme os erros aparecerem nos testes
    };
    if (mapaFonetico.containsKey(ultima)) return mapaFonetico[ultima]!;

    // se já é uma letra única, retorna ela
    if (ultima.length == 1) return ultima;

    // fallback: pega o primeiro caractere
    return ultima.substring(0, 1);
  }

  void _speech2AfterGettingText(String result) {
    final letraReconhecida = _extrairLetra(result);

    setState(() {
      _label4 = letraReconhecida;
      _letraReconhecida = letraReconhecida;
      _estaOuvindo = false;
    });

    String letraCorretaUp = _letraCorreta.trim().toUpperCase();

    if (letraCorretaUp == letraReconhecida) {
      final proximoIndex = _indexAtual + 1;
      final chegouAoSeparador =
          proximoIndex < _letras.length && _letras[proximoIndex] == ' ';
      final chegouAoFim = proximoIndex >= _letras.length;

      if (!chegouAoSeparador && !chegouAoFim) {
        Vibration.vibrate(duration: 200);
      }
      _indexAtual++;
      _enviarProximaLetra();
    } else {
      Vibration.vibrate(duration: 2000);
    }
  }

  void _onBotaoFalar() {
    if (!_speechDisponivel || _estaOuvindo) return;

    setState(() {
      _estaOuvindo = true;
    });

    _speech1.listen(
      localeId: 'pt_BR',
      onResult: (result) {
        if (result.finalResult) {
          _speech1.stop(); //encerra completamente o reconhecimento
          setState(() {
            _estaOuvindo = false;
          });
          _processarPalavra(result.recognizedWords);
        }
      },
    );
  }

  void _processarPalavra(String palavra) {
    final texto = palavra.trim().toUpperCase();
    final palavras = texto.split(RegExp(r'\s+'));
    final letras = <String>[];

    for (final palavraAtual in palavras) {
      final letrasDaPalavra = palavraAtual
          .split('')
          .where((caractere) => RegExp(r'[A-ZÀ-ÖØ-Þ]').hasMatch(caractere))
          .toList();

      if (letrasDaPalavra.isEmpty) continue;
      if (letras.isNotEmpty) letras.add(' ');
      letras.addAll(letrasDaPalavra);
    }

    if (letras.isEmpty) return;

    _trocaPalavraTimer?.cancel();

    setState(() {
      _letras = letras;
      _indexAtual = 0;
      _palavraCapturada = true;
      _aguardandoFeedback = true;
      _entradaEhFrase = letras.contains(' ');
    });

    _enviarProximaLetra();
  }

  void _processarTextoDigitado([String? texto]) {
    final palavra = (texto ?? _textController.text).trim();
    if (palavra.isEmpty) return;

    FocusScope.of(context).unfocus();
    _processarPalavra(palavra);
  }

  void _enviarProximaLetra() {
    if (_indexAtual >= _letras.length) {
      setState(() {
        _label5 = _entradaEhFrase ? 'FIM DA FRASE' : 'FIM DA PALAVRA';
        _palavraCapturada = false;
        _aguardandoFeedback = false;
      });

      if (_entradaEhFrase) {
        Vibration.vibrate(pattern: [0, 250, 150, 250, 150, 500]);
      }
      return;
    }

    String letra = _letras[_indexAtual];

    if (letra == ' ') {
      _indexAtual++;
      setState(() {
        _label5 = 'PRÓXIMA PALAVRA';
        _aguardandoFeedback = false;
      });

      Vibration.vibrate(pattern: [0, 180, 120, 180]);
      _trocaPalavraTimer?.cancel();
      _trocaPalavraTimer = Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        setState(() => _aguardandoFeedback = true);
        _enviarProximaLetra();
      });
      return;
    }

    setState(() {
      _letraCorreta = letra;
      _ultimaLetraEnviada = letra;
      _label5 = letra;
    });

    _enviarBT(letra);
  }

  void _onTextChanged() {
    setState(() {
      _label1 = _textController.text;
      _label3 = _ultimaLetraEnviada;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PitMed',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF3F51B5),
        elevation: 4,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _listarDispositivos,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F51B5),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Conectar Bluetooth'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _processarTextoDigitado,
                      decoration: InputDecoration(
                        hintText: 'Digite "letra x"',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Iniciar palavra digitada',
                          onPressed: _processarTextoDigitado,
                          icon: const Icon(Icons.send),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 70,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_label1, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (_label3.isNotEmpty)
                    Text(_label3,
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _label2,
                      style: TextStyle(
                        fontSize: 13,
                        color: _label2.contains('conectado') ||
                                _label2.contains('Enviada')
                            ? Colors.green
                            : _label2.contains('Falha') ||
                                    _label2.contains('desconectado')
                                ? Colors.red
                                : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3F51B5)),
                ),
                child: Text(
                  _label5,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF3F51B5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Debug: mostra exatamente o que o reconhecimento de voz
              // captou na última tentativa, pra sabermos se o problema é
              // a transcrição ou a comparação.
              if (_label4.isNotEmpty)
                Text(
                  'Reconhecido: "$_label4"',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.9,
                    heightFactor: 0.9,
                    child: GestureDetector(
                      onTap: _onBotaoFalar,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _estaOuvindo
                              ? Colors.red.shade400
                              : const Color(0xFF3F51B5),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _estaOuvindo ? Icons.mic : Icons.mic_none,
                              color: Colors.white,
                              size: 72,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _estaOuvindo ? 'Ouvindo...' : 'Toque para falar',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bluetooth,
                    color: _btConectado ? Colors.blue : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _btConectado
                        ? 'Bluetooth conectado'
                        : 'Sem conexão Bluetooth',
                    style: TextStyle(
                      fontSize: 12,
                      color: _btConectado ? Colors.blue : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
