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

  // ── Labels ─────────────────────────────────────────────────
  String _label1 =
      'Conecte-se ao dispositivo bluetooth PitMed para enviar as mensagens ao Equipamento de comunicação.';
  String _label2 = '';
  String _label3 = '';
  String _label4 = '';
  String _label5 = 'Aqui aparecerá a letra de comparação';

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
    await _speech2.initialize();
    setState(() => _speechDisponivel = ok);

    _clockTimer = null;
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

  /*void _clockTick() {
    if (!_btConectado || _connection == null) return;

    if (_mensagemRecebida.contains('PRESS') && !_estaOuvindo) {
      setState(() {
        _estaOuvindo = true;
        _mensagemRecebida = '';
      });
      _speech2GetText();
    }

    if (_mensagemRecebida.contains('RELEASE') && _estaOuvindo) {
      setState(() {
        _estaOuvindo = false;
        _mensagemRecebida = '';
      });
      _speech2Stop();
    }
  }*/

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

  void _processarComandoBluetooth(String msg) {
    if (msg.contains('PRESS') && !_estaOuvindo) {
      _iniciarReconhecimento();
    }

    if (msg.contains('RELEASE') && _estaOuvindo) {
      _pararReconhecimento();
    }
  }

  void _iniciarReconhecimento() async {
    await _speech1.stop();

    setState(() => _estaOuvindo = true);

    _speechTimeout?.cancel();

    _speechTimeout = Timer(const Duration(seconds: 5), () {
      _pararReconhecimento();
    });

    _speech1.listen(
      localeId: 'pt_BR',
      listenMode: ListenMode.confirmation,
      onResult: (result) {
        if (result.finalResult) {
          setState(() => _estaOuvindo = false);
          _processarPalavra(result.recognizedWords);
        }
      },
    );
  }

  void _pararReconhecimento() {
    _speech1.stop();
    setState(() => _estaOuvindo = false);
  }

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

          if (_bufferBT.contains('PRESS') || _bufferBT.contains('RELEASE')) {
            _processarComandoBluetooth(_bufferBT);
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

  void _enviarBT(String texto) {
    if (_btConectado && _connection != null) {
      _connection!.output.add(Uint8List.fromList(texto.codeUnits));
    }
  }

  void _onBotaoEnviar() {
    String resposta = _ultimaLetraEnviada.trim().toUpperCase();
    String correta = _letraCorreta.trim().toUpperCase();

    setState(() {
      _label2 = _btConectado
          ? 'Mensagem Enviada'
          : 'Falha ao enviar a mensagem. Cheque sua conexão bluetooth.';
    });

    if (resposta == correta) {
      Vibration.vibrate(duration: 200);
      _indexAtual++;
      _enviarProximaLetra();
    } else {
      Vibration.vibrate(duration: 2000);
    }
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

  // void _onBotaoFalar() => _speech2GetText();

  void _speech2GetText() {
    if (!_speechDisponivel) return;
    _speech2.listen(
      onResult: (result) {
        if (result.finalResult) {
          _speech2AfterGettingText(result.recognizedWords);
        }
      },
      localeId: 'pt_BR',
    );
  }

  void _speech2Stop() {
    _speech2.stop();
    String letraCorretaUp = _letraCorreta.trim().toUpperCase();
    String ultimaUp = _ultimaLetraEnviada.trim().toUpperCase();

    if (letraCorretaUp == ultimaUp) {
      Vibration.vibrate(duration: 200);
      _indexAtual++;
      _verificarFimDaPalavra();
    } else {
      Vibration.vibrate(duration: 2000);
    }
  }

  void _speech2AfterGettingText(String result) {
    setState(() => _label4 = '');
    if (_label4.isEmpty) {
      setState(() => _label4 = result);
      List<String> letras = result.split('');
      setState(() {
        _letras = letras;
        _indexAtual = 1;
      });
      if (_letras.isNotEmpty) {
        String primeiraLetra = _letras[0];
        setState(() {
          _label5 = primeiraLetra;
          _letraCorreta = ' ${primeiraLetra.toUpperCase()}';
        });
        _enviarBT(_label5);
      }
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
          setState(() {
            _estaOuvindo = false;
          });
          _processarPalavra(result.recognizedWords);
        }
      },
    );
  }

  void _processarPalavra(String palavra) {
    setState(() {
      _letras = palavra.toUpperCase().split('');
      _indexAtual = 0;
      _palavraCapturada = true;
    });

    _enviarProximaLetra();
  }

  void _enviarProximaLetra() {
    if (_indexAtual >= _letras.length) {
      setState(() {
        _label5 = "FIM DA PALAVRA";
        _palavraCapturada = false;
      });
      return;
    }

    String letra = _letras[_indexAtual];

    setState(() {
      _letraCorreta = letra;
      _label5 = letra;
    });

    _enviarBT(letra);
  }

  void _onBotaoFeedbackFisico(String letraRecebida) {
    if (!_palavraCapturada) return;

    String correta = _letraCorreta.trim().toUpperCase();
    String resposta = letraRecebida.trim().toUpperCase();

    if (resposta == correta) {
      Vibration.vibrate(duration: 200);
      _indexAtual++;
      _enviarProximaLetra();
    } else {
      Vibration.vibrate(duration: 2000);
    }
  }

  void _verificarFimDaPalavra() {
    if (_indexAtual > _letras.length) {
      setState(() {
        _label5 = 'FIM DA PALAVRA';
        _label1 = '';
        _textController.text = '';
      });
      Vibration.vibrate(duration: 700);
    } else {
      String proxLetra = _letras[_indexAtual - 1];
      setState(() {
        _label5 = proxLetra;
        _letraCorreta = ' ${proxLetra.toUpperCase()}';
      });
      _enviarBT(_label5);
    }
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
                      decoration: const InputDecoration(
                        hintText: 'Digite "letra x"',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _onBotaoFeedback,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Feedback', style: TextStyle(fontSize: 16)),
                ),
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _onBotaoEnviar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Enviar', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3F51B5)),
                  ),
                  child: Text(
                    _label5,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF3F51B5),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Center(
                child: GestureDetector(
                  onTap: _onBotaoFalar,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 150,
                    height: 80,
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
                          size: 30,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _estaOuvindo ? 'Ouvindo...' : 'Toque para falar',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
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
