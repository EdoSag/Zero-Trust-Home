import 'package:flutter/material.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// Home in the suite. Not in the core's `ZtSuite` list yet, so the other
/// apps don't link to it before it's released.
const ZtSuiteApp homeSuiteApp = ZtSuiteApp(
  appId: 'home',
  name: 'Home',
  tagline: 'Private, local-first smart home control',
  icon: Icons.home_outlined,
  accent: Color(0xFFF59E0B), // amber
  androidPackage: 'dev.sagron.zerotrusthome',
);

const ZtAppConfig homeAppConfig = ZtAppConfig(
  appId: 'home',
  displayName: 'Zero-Trust Home',
  accent: Color(0xFFF59E0B),
);
