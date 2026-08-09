import 'package:flutter/material.dart';

import '../repositories/match_repository.dart';
import '../models/match_model.dart';

class ApiTestScreen extends StatelessWidget {
  const ApiTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("API Sports Test")),
      body: FutureBuilder<List<MatchModel>>(
        future: MatchRepository.getTodayMatches(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(snapshot.error.toString()),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Nessuna partita trovata"));
          }

          final matches = snapshot.data!;

          return ListView.builder(
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];

              return ListTile(
                leading: const Icon(Icons.sports_soccer),
                title: Text("${match.homeTeam} - ${match.awayTeam}"),
                subtitle: Text(match.league),
              );
            },
          );
        },
      ),
    );
  }
}
