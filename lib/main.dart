import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// Import conditionnel avec des fichiers séparés
import 'web_js_stub.dart' if (dart.library.js) 'web_js_impl.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Alphai Robot Firmware Updater',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const WebSerialUpdateScreen(),
    );
  }
}



class WebSerialUpdateScreen extends StatefulWidget {
  const WebSerialUpdateScreen({super.key});
  @override
  State<WebSerialUpdateScreen> createState() => _WebSerialUpdateScreenState();
}

class _WebSerialUpdateScreenState extends State<WebSerialUpdateScreen> 
    with TickerProviderStateMixin {
  final baudCtrl = TextEditingController(text: '921600');
  String status = 'Votre robot Alphai est prêt à être mis à jour';
  double progress = 0;
  bool busy = false;
  String? chip;
  bool isDarkMode = false; // Mode sombre par défaut
  
  // Variables pour la progression détaillée
  String detailedStatus = '';
  double detailedProgress = 0;
  int currentFileIndex = 0;
  int totalFiles = 3; // bootloader + partition + app.bin
  String currentOperation = '';
  
  // Info du firmware depuis l'API
  String? firmwareVersion;
  String? firmwareDescription;

  // Contrôleurs d'animation
  late AnimationController _floatingController;
  late AnimationController _pulseController;
  late AnimationController _connectionController;
  late AnimationController _glowController;
  
  // Animations
  late Animation<double> _floatingAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _connectionAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    // Utiliser WidgetsBinding.instance pour éviter l'erreur dependOnInheritedWidgetOfExactType dans initState
    isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  void _setupAnimations() {
    // Animation de flottement pour l'icône robot
    _floatingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _floatingAnimation = Tween<double>(
      begin: 0,
      end: 10,
    ).animate(CurvedAnimation(
      parent: _floatingController,
      curve: Curves.easeInOut,
    ));
    _floatingController.repeat(reverse: true);

    // Animation de pulsation pour les halos
    _pulseController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    _pulseController.repeat(reverse: true);

    // Animation de connexion
    _connectionController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _connectionAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _connectionController,
      curve: Curves.elasticOut,
    ));

    // Animation de lueur
    _glowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _glowAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));
    _glowController.repeat(reverse: true);
  }

  @override
  void dispose() {
    baudCtrl.dispose();
    _floatingController.dispose();
    _pulseController.dispose();
    _connectionController.dispose();
    _glowController.dispose();
    
    // Nettoyer le callback JavaScript
    if (kIsWeb) {
      try {
        WebJS.setProperty(WebJS.globalThis, 'flutterProgressCallback', null);
      } catch (_) {}
    }
    super.dispose();
  }

  // ————— JS interop helpers —————
  Future<void> _awaitEspReady() async {
    if (!kIsWeb) return;
    
    final ready = WebJS.getProperty(WebJS.globalThis, 'espReady');
    if (ready != null) {
      await Future.any([
        WebJS.promiseToFuture(ready),
        Future.delayed(const Duration(seconds: 10), () {
          throw TimeoutException('Init flasheur trop longue (espReady).');
        }),
      ]);
    }
  }

  void _setupProgressCallback() {
    if (!kIsWeb) return;
    
    // Création d'un callback Dart vers JavaScript pour recevoir les mises à jour de progression
    final progressCallback = WebJS.allowInterop((String operation, int fileIndex, int written, int total) {
      if (mounted) {
        setState(() {
          currentOperation = operation;
          currentFileIndex = fileIndex;
          detailedProgress = total > 0 ? (written / total) : 0;
          
          // Calcul de la progression globale
          double globalProgress = 0;
          if (operation == 'bootloader') {
            globalProgress = 0.1 + (detailedProgress * 0.2); // 10-30%
          } else if (operation == 'partition') {
            globalProgress = 0.3 + (detailedProgress * 0.1); // 30-40%
          } else if (operation == 'app') {
            globalProgress = 0.4 + (detailedProgress * 0.5); // 40-90%
          }
          
          progress = globalProgress.clamp(0.0, 0.9);
          
          detailedStatus = '$written/$total bytes';
          
          if (operation == 'bootloader') {
            status = 'Installation du système de base…';
          } else if (operation == 'partition') {
            status = 'Installation de la table de partitions…';
          } else if (operation == 'app') {
            status = firmwareVersion != null 
              ? 'Installation du firmware Alphai v$firmwareVersion…'
              : 'Installation du firmware Alphai…';
          }
        });
      }
    });
    
    // Exposer le callback au JavaScript
    WebJS.setProperty(WebJS.globalThis, 'flutterProgressCallback', progressCallback);
  }

  // ————— Actions —————
  Future<void> _connect() async {
    if (!kIsWeb) {
      setState(() => status = 'Cette fonctionnalité nécessite un navigateur web (Web Serial)');
      return;
    }
    if (chip != null) {
      // On ferme explicitement, au cas où
      try {
        if (kIsWeb) {
          final p = WebJS.callMethod(WebJS.globalThis, 'espDisconnectAsync', []);
          await WebJS.promiseToFuture(p);
        }
      } catch (_) {}
      setState(() { chip = null; });
    }
    setState(() {
      busy = true;
      status = 'Recherche de votre robot Alphai…';
      progress = 0;
      detailedProgress = 0;
      currentFileIndex = 0;
      currentOperation = '';
      detailedStatus = '';
    });

    try {
      await _awaitEspReady();

      if (!kIsWeb) {
        throw StateError('Cette fonctionnalité n\'est disponible que sur le web');
      }

      if (!WebJS.hasProperty(WebJS.globalThis, 'espConnectAsync')) {
        throw StateError('Module de mise à jour indisponible');
      }

      final baud = int.tryParse(baudCtrl.text.trim()) ?? 115200;
      setState(() => status = 'Connexion au robot Alphai via USB…');

      final promise = WebJS.callMethod(WebJS.globalThis, 'espConnectAsync', [baud]);
      final r = await WebJS.promiseToFuture(promise);

      setState(() {
        chip = r?.toString();
        status = 'Alphai est connecté et prêt pour la mise à jour';
        progress = 0;
      });
      
      // Animation de connexion réussie
      _connectionController.forward();
      
      // Récupérer les infos du firmware disponible
      _fetchFirmwareInfo();
    } catch (e) {
      setState(() => status = 'Impossible de se connecter au robot: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _fetchFirmwareInfo() async {
    if (!kIsWeb) return;
    
    try {
      if (WebJS.hasProperty(WebJS.globalThis, 'espGetLatestFirmwareInfoAsync')) {
        setState(() => status = 'Récupération des informations du firmware…');
        
        final promise = WebJS.callMethod(WebJS.globalThis, 'espGetLatestFirmwareInfoAsync', []);
        final result = await WebJS.promiseToFuture(promise);
        
        if (result != null) {
          final version = WebJS.getProperty(result, 'version')?.toString();
          final description = WebJS.getProperty(result, 'description')?.toString();
          
          setState(() {
            firmwareVersion = version;
            firmwareDescription = description;
            status = firmwareVersion != null 
              ? 'Firmware disponible : v$firmwareVersion - Prêt pour la mise à jour'
              : 'Alphai est connecté et prêt pour la mise à jour';
          });
        }
      }
    } catch (e) {
      print('Erreur lors de la récupération des infos firmware: $e');
      // Non bloquant, on continue même si ça échoue
      setState(() => status = 'Alphai est connecté et prêt pour la mise à jour');
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      busy = true;
      status = 'Déconnexion du robot Alphai…';
    });
    try {
      await _awaitEspReady();
      if (kIsWeb && WebJS.hasProperty(WebJS.globalThis, 'espDisconnectAsync')) {
        final p = WebJS.callMethod(WebJS.globalThis, 'espDisconnectAsync', []);
        await WebJS.promiseToFuture(p);
      }
      setState(() {
        chip = null;
        progress = 0;
        detailedProgress = 0;
        currentFileIndex = 0;
        currentOperation = '';
        detailedStatus = '';
        status = 'Robot déconnecté';
      });
      _connectionController.reset();
    } catch (e) {
      setState(() => status = 'Erreur lors de la déconnexion: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _flash() async {
    if (chip == null) {
      setState(() => status = 'Veuillez d\'abord connecter votre robot Alphai');
      return;
    }
    
    setState(() {
      busy = true;
      progress = 0;
      detailedProgress = 0;
      currentFileIndex = 0;
      currentOperation = '';
      detailedStatus = '';
      status = 'Préparation de la mise à jour du robot Alphai…';
    });
    
    try {
      // Empêcher la mise en veille pendant la mise à jour
      if (kIsWeb) {
        await WakelockPlus.enable();
      }

      if (!kIsWeb) {
        throw StateError('Cette fonctionnalité n\'est disponible que sur le web');
      }

      // Configuration du callback de progression
      _setupProgressCallback();

      // Flash TOUT en UNE SEULE FOIS (bootloader + partition + app)
      // Comme le fait PlatformIO - c'est la méthode correcte !
      setState(() => status = 'Installation du firmware complet (bootloader + système + app)…');
      
      if (!WebJS.hasProperty(WebJS.globalThis, 'espFlashFixedAsync')) {
        throw StateError('Module de mise à jour indisponible');
      }

      final opts = WebJS.jsify({'verify': true, 'eraseAll': false});
      final promise = WebJS.callMethod(WebJS.globalThis, 'espFlashFixedAsync', [opts]);
      final result = await WebJS.promiseToFuture(promise);
      
      // Récupérer la version depuis le résultat
      String? installedVersion;
      if (result != null) {
        try {
          installedVersion = WebJS.getProperty(result, 'version')?.toString();
        } catch (_) {}
      }

      setState(() {
        progress = 0.9;
        status = installedVersion != null 
          ? 'Firmware v$installedVersion installé • Redémarrage du robot…'
          : 'Firmware installé • Redémarrage du robot…';
        currentOperation = 'reset';
        detailedStatus = 'Finalisation de la mise à jour…';
      });

      // Reset optionnel
      if (WebJS.hasProperty(WebJS.globalThis, 'espResetAsync')) {
        try {
          final promise3 = WebJS.callMethod(WebJS.globalThis, 'espResetAsync', []);
          await WebJS.promiseToFuture(promise3);
        } catch (e) {
          print('Reset failed (non-critical): $e');
        }
      }

      setState(() {
        progress = 1;
        status = installedVersion != null
          ? '🎉 Mise à jour v$installedVersion terminée avec succès ! Votre robot Alphai est prêt.'
          : '🎉 Mise à jour terminée avec succès ! Votre robot Alphai est prêt.';
        detailedStatus = installedVersion != null
          ? 'Robot Alphai v$installedVersion mis à jour et opérationnel'
          : 'Robot Alphai mis à jour et opérationnel';
        currentOperation = 'complete';
      });
      
    } catch (e) {
      setState(() {
        status = 'Erreur lors de la mise à jour: $e';
        detailedStatus = 'Veuillez réessayer ou contacter le support';
      });
    } finally {
      if (kIsWeb) {
        await WakelockPlus.disable();
      }
      setState(() => busy = false);
    }
  }

  // ————— Helpers —————
  void _toggleTheme() {
    debugPrint('Basculement du thème: ${isDarkMode ? 'vers clair' : 'vers sombre'}');
    if (mounted) {
      setState(() {
        isDarkMode = !isDarkMode;
      });
      debugPrint('Nouveau mode: ${isDarkMode ? 'sombre' : 'clair'}');
    }
  }

  String _getOperationLabel(String operation) {
    switch (operation) {
      case 'bootloader':
        return 'Installation du système de base';
      case 'app':
        return 'Installation du firmware Alphai';
      case 'transition':
        return 'Préparation de l\'étape suivante';
      case 'reset':
        return 'Redémarrage du robot Alphai';
      case 'complete':
        return 'Mise à jour terminée';
      default:
        return operation;
    }
  }

  // ————— UI —————
  @override
  Widget build(BuildContext context) {
    final connected = chip != null;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Stack(
            children: [
              // Fond ultra premium avec dégradés dynamiques
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDarkMode ? [
                      const Color(0xFF000000),
                      const Color(0xFF0A0A0B),
                      const Color(0xFF111115),
                    ] : [
                      const Color(0xFFF8F9FA),
                      const Color(0xFFFFFFFF),
                      const Color(0xFFF0F1F3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),

              
              
              // Particules animées en arrière-plan
              ..._buildFloatingParticles(),
              
              // Halos dynamiques ultra modernes
              Positioned(
                right: -200,
                top: -100,
                child: _buildAnimatedHalo(
                  color: (isDarkMode 
                    ? const Color(0xFF007AFF) 
                    : const Color(0xFF007AFF).withOpacity(0.6)
                  ).withOpacity(0.3 * _pulseAnimation.value),
                  size: 400,
                ),
              ),
              Positioned(
                left: -160,
                bottom: -120,
                child: _buildAnimatedHalo(
                  color: (isDarkMode 
                    ? const Color(0xFF30D158) 
                    : const Color(0xFF34C759).withOpacity(0.6)
                  ).withOpacity(0.25 * _pulseAnimation.value),
                  size: 350,
                ),
              ),
              Positioned(
                right: 100,
                bottom: -80,
                child: _buildAnimatedHalo(
                  color: (isDarkMode 
                    ? const Color(0xFFFF453A) 
                    : const Color(0xFFFF3B30).withOpacity(0.6)
                  ).withOpacity(0.2 * _pulseAnimation.value),
                  size: 280,
                ),
              ),

              // Contenu principal
              SafeArea(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            
                            const SizedBox(height: 80),
                            
                            // Robot ILO central avec animations
                            _buildCentralRobot(connected),
                            
                            const SizedBox(height: 30),
                            
                            // Statut principal avec typographie Apple
                            _buildStatusSection(),
                            
                            const SizedBox(height: 20),
                            
                            // Info firmware disponible
                            if (connected && firmwareVersion != null && !busy) ...[
                              _buildFirmwareInfoCard(),
                              const SizedBox(height: 20),
                            ],
                            
                            // Carte de progression ultra moderne
                            if ((busy || progress > 0) && connected) ...[
                              _buildProgressCard(),
                              const SizedBox(height: 20),
                            ],
                            
                            // Actions principales
                            _buildActionButtons(connected),
                            
                            const SizedBox(height: 40),
                            
                            // Footer minimaliste
                            _buildFooter(),
                            
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Bouton de basculement de thème en haut à droite
              Positioned(
                top: 20,
                right: 20,
                child: SafeArea(
                  child: _buildThemeToggleButton(),
                ),
              ),
            ],
          );
        },
      ),
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
    );
  }

  // ————— Widgets stylés ultra modernes —————
  
  Widget _buildThemeToggleButton() {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDarkMode 
          ? Colors.white.withOpacity(0.15) 
          : Colors.black.withOpacity(0.15),
        border: Border.all(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.3) 
            : Colors.black.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkMode 
              ? Colors.white.withOpacity(0.1) 
              : Colors.black.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            debugPrint('🎯 Bouton thème cliqué !');
            _toggleTheme();
          },
          borderRadius: BorderRadius.circular(28),
          splashColor: isDarkMode 
            ? Colors.white.withOpacity(0.2) 
            : Colors.black.withOpacity(0.2),
          highlightColor: isDarkMode 
            ? Colors.white.withOpacity(0.1) 
            : Colors.black.withOpacity(0.1),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return RotationTransition(
                  turns: animation,
                  child: child,
                );
              },
              child: Icon(
                isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                key: ValueKey(isDarkMode),
                color: isDarkMode ? Colors.amber[300] : Colors.indigo[400],
                size: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFloatingParticles() {
    return List.generate(8, (index) {
      return AnimatedBuilder(
        animation: _floatingController,
        builder: (context, child) {
          final offset = _floatingAnimation.value * (index.isEven ? 1 : -1);
          return Positioned(
            left: 50.0 * index + offset,
            top: 100.0 * (index % 3) + offset * 0.5,
            child: Opacity(
              opacity: 0.1,
              child: Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildAnimatedHalo({required Color color, required double size}) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          width: size * _glowAnimation.value,
          height: size * _glowAnimation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, Colors.transparent],
              stops: const [0.0, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCentralRobot(bool connected) {
    return AnimatedBuilder(
      animation: Listenable.merge([_floatingAnimation, _connectionAnimation]),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatingAnimation.value),
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  connected 
                    ? const Color(0xFF30D158).withOpacity(0.3)
                    : (isDarkMode 
                        ? const Color(0xFF8E8E93).withOpacity(0.3)
                        : const Color(0xFF8E8E93).withOpacity(0.2)),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
            child: Center(
              child: AnimatedScale(
                scale: connected ? 1.0 + (_connectionAnimation.value * 0.1) : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset("assets/images/robot.png")
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode 
          ? Colors.white.withOpacity(0.02) 
          : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.08) 
            : Colors.black.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          if (busy)...[
            Text("⚠️ Ne quittez pas, nous mettons à jour votre appareil.", style: GoogleFonts.roboto(
              color: isDarkMode 
                ? Colors.white.withOpacity(0.6) 
                : Colors.black.withOpacity(0.6),
              fontSize: 14,
              height: 1.3,
            )),
            const SizedBox(height: 20),
          ],
          Text(
            status,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: isDarkMode ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmwareInfoCard() {
    final primaryColor = isDarkMode ? Colors.blueAccent : Colors.blue;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode 
          ? primaryColor.withOpacity(0.1)
          : primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.system_update_alt_rounded,
              color: primaryColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version $firmwareVersion disponible',
                  style: GoogleFonts.poppins(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (firmwareDescription != null && firmwareDescription!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    firmwareDescription!,
                    style: GoogleFonts.roboto(
                      color: isDarkMode 
                        ? Colors.white.withOpacity(0.6) 
                        : Colors.black.withOpacity(0.6),
                      fontSize: 13,
                      height: 1.3,
                    ),
                    maxLines: 20,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode 
          ? Colors.white.withOpacity(0.03) 
          : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.1) 
            : Colors.black.withOpacity(0.12),
        ),
      ),
      child: Column(
        children: [
          // Progression principale
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progression totale',
                style: GoogleFonts.poppins(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: GoogleFonts.poppins(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Barre de progression principale avec animations
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: isDarkMode 
                ? Colors.white.withOpacity(0.05) 
                : Colors.black.withOpacity(0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 0.9 
                    ? const Color(0xFF30D158)
                    : Color(0xFF007AFF),
                ),
              ),
            ),
          ),

          // Progression détaillée si disponible
          if (busy && currentOperation.isNotEmpty && currentOperation != 'complete') ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _getOperationLabel(currentOperation),
                    style: GoogleFonts.roboto(
                      color: isDarkMode 
                        ? Colors.white.withOpacity(0.7) 
                        : Colors.black.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${(detailedProgress * 100).round()}%',
                  style: GoogleFonts.roboto(
                    color: isDarkMode 
                      ? Colors.white.withOpacity(0.9) 
                      : Colors.black.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: isDarkMode 
                  ? Colors.white.withOpacity(0.05) 
                  : Colors.black.withOpacity(0.08),
                borderRadius: BorderRadius.circular(2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: detailedProgress,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF30D158),
                  ),
                ),
              ),
            ),
            
            // Affichage des bytes sous la barre détaillée
            if (detailedStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    detailedStatus,
                    style: GoogleFonts.roboto(
                      color: isDarkMode 
                        ? Colors.white.withOpacity(0.6) 
                        : Colors.black.withOpacity(0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool connected) {
    return Column(
      children: [
        // Boutons d'action principaux
        Row(
          children: [
            Expanded(
              child: _modernButton(
                onPressed: busy ? null : _connect,
                label: connected ? 'Reconnecter' : 'Connecter',
                icon: Icons.usb_rounded,
                isPrimary: !connected,
                color: const Color(0xFF007AFF)
              ),
            ),
            if (connected) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _modernButton(
                  onPressed: busy ? null : _disconnect,
                  label: 'Déconnecter',
                  icon: Icons.link_off_rounded,
                  isPrimary: false,
                  color: const Color(0xFF8E8E93),
                ),
              ),
            ],
          ],
        ),

        if (connected && !busy && currentOperation != 'complete') ...[
          const SizedBox(height: 12),
          Row(
            children: [
                Expanded(
                  child: _modernButton(
                    onPressed: busy ? null : _flash,
                    label: 'Mettre à jour',
                    icon: Icons.system_update_rounded,
                    isPrimary: true,
                    color: const Color(0xFF30D158),
                  ),
                ),
            ],
          ),
        ],
        
        const SizedBox(height: 12),

        const SizedBox(height: 30),
        _buildConnectionGuide(),
        
        const SizedBox(height: 12),
        
        // Info technique
        if (!busy)
          Text(
            'Nécessite Chrome/Edge',
            style: GoogleFonts.roboto(
              color: isDarkMode 
                ? Colors.white.withOpacity(0.4) 
                : Colors.black.withOpacity(0.4),
              fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _modernButton({
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    required bool isPrimary,
    required Color color,
    bool isCompact = false,
  }) {
    final isEnabled = onPressed != null;
    
    return Container(
      height: isCompact ? 50 : 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: isPrimary && isEnabled
          ? LinearGradient(
              colors: [color, color.withOpacity(0.8)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            )
          : null,
        color: isPrimary 
          ? null 
          : (isEnabled ? color.withOpacity(0.1) : Colors.white.withOpacity(0.03)),
        border: Border.all(
          color: isPrimary 
            ? Colors.transparent 
            : (isEnabled ? color.withOpacity(0.3) : Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 20,
              vertical: 16,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: isCompact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(
                  icon,
                  color: isPrimary 
                    ? Colors.white 
                    : (isEnabled ? color : Colors.white.withOpacity(0.3)),
                  size: 20,
                ),
                if (!isCompact) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: isPrimary 
                        ? Colors.white 
                        : (isEnabled ? color : Colors.white.withOpacity(0.3)),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionGuide() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode 
          ? Colors.white.withOpacity(0.03) 
          : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode 
            ? Colors.white.withOpacity(0.1) 
            : Colors.black.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comment mettre à jour le code ESP32',
            style: GoogleFonts.poppins(
              color: isDarkMode ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          
          // Section FTDI
          Text(
            'Utilisation d\'un FTDI',
            style: GoogleFonts.poppins(
              color: isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          
          // Requirements
          Text(
            'Prérequis :',
            style: GoogleFonts.roboto(
              color: isDarkMode ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
              fontWeight: FontWeight.bold,
            ),
          ),
          _buildBulletPoint('Adaptateur FTDI'),
          _buildBulletPoint('4 câbles Dupont mâle-femelle'),
          
          const SizedBox(height: 16),
          
          // FTDI Cable & Image
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Câblage :',
                      style: GoogleFonts.roboto(
                        color: isDarkMode ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildBulletPoint('RX'),
                    _buildBulletPoint('TX'),
                    _buildBulletPoint('VCC'),
                    _buildBulletPoint('GND'),
                  ],
                ),
              ),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(8),
                child: Image.asset('assets/images/ftdi_cable.png'),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Divider(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          const SizedBox(height: 24),

          // Section Flashing
          Text(
            'Flasher l\'ESP',
            style: GoogleFonts.poppins(
              color: isDarkMode ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildNumberedPoint(1, 'Éteindre l\'ESP'),
          _buildNumberedPoint(2, 'Maintenir le bouton BOOT enfoncé tout en connectant le câble USB'),
          _buildNumberedPoint(3, 'Cliquer sur "Connecter" dans l\'application'),
          _buildNumberedPoint(4, 'Une fois connecté, cliquer sur "Mettre à jour" pour flasher le firmware'),
          _buildNumberedPoint(5, 'Attendre la fin du processus sans déconnecter l\'ESP'),
          _buildNumberedPoint(6, 'Appuyez sur le bouton RESET de l\'ESP pour redémarrer avec le nouveau firmware'),
          
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
              ),
              child: Image.asset('assets/images/schema.png', fit: BoxFit.cover),
              
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 8),
      child: Row(
        children: [
          Container(
            width: 4, 
            height: 4, 
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6),
              shape: BoxShape.circle
            )
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.roboto(
                color: isDarkMode ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberedPoint(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: GoogleFonts.roboto(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.roboto(
                color: isDarkMode ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDarkMode 
              ? Colors.white.withOpacity(0.02) 
              : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF30D158),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Alphai Robot Firmware Updater',
                style: GoogleFonts.roboto(
                  color: isDarkMode 
                    ? Colors.white.withOpacity(0.6) 
                    : Colors.black.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
