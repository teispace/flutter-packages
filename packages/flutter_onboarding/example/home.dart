import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter OnBoarding'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('Maintained by Teispace & Open Source Community 🚀 '),
      ),
    );
  }
}
