import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class ScannedLabels {
  final int? id;   //"?" makes it nullable so SQL can autoincrement the ID
  final String text;
  final String times;

  const ScannedLabels({this.id, required this.text, required this.times});
  //translates Dart object into a format SQLite
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'text': text,
      'scannedAt': times,
    };
  }
  //translates SQLite format back into your Dart object
  factory ScannedLabels.fromMap(Map<String, dynamic> map) {
    return ScannedLabels(
      id: map['id'] as int?,
      text: map['text'] as String,
      times: map['scannedAt'] as String,
    );
  }
}

class DatabaseService {

  // A variable to hold our active database connection
  Database? _database;
  //A getter to retrieve the database. If it doesn't exist, creates one
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }
  //function to open database
  Future<Database> initDatabase() async {

    //open database
    final database = openDatabase(
      join(await getDatabasesPath(), 'ScannedLabels_database.db'),      //join function used to join path with database name in this case ScannedLabels_database.db

      // create a table
      onCreate: (db, version) {
        // running the CREATE TABLE statement on the database.
        return db.execute(
          'CREATE TABLE scanned_labelsTB(id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT, scannedAt TEXT)',
        );

      },
  // Set the version. This executes the onCreate function and provides a
  // path to perform database upgrades and downgrades.
  version: 1,
    );
    return database;
  }
    //Insert functions
  Future<void> insertLabels(ScannedLabels labels) async {     //can change void to int to allow debugging option
    // Get a reference to the database.
    final db = await database;

    await db.insert(
      'scanned_labelsTB',
      labels.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  
  // Output function that 
    Future<List<ScannedLabels>> outPutLabels({
      String? whereClause,
      List<Object?>? whereArgs,
      String? orderBy = 'id DESC', 
      int? limitCount,
    }) async {
      final db = await database;

      final List<Map<String, dynamic>> labelMaps = await db.query(
        'scanned_labelsTB',
        where: whereClause,               //whereClause = id = ? and whereArgs : [5] will become 'WHERE id = 5'
        whereArgs: whereArgs,             
        orderBy: orderBy,
        limit: limitCount,
      );

      return List.generate(labelMaps.length, (i) {
        return ScannedLabels.fromMap(labelMaps[i]);
      });
    }

  Future<void> deleteLabel(int id) async {
  // Get a reference to the database.
  final db = await database;

  // Remove the Dog from the database.
  await db.delete(
    'scanned_labelsTB',
    // Use a `where` clause to delete a specific dog.
    where: 'id = ?',
    // Pass the id as a whereArg to prevent SQL injection.
    whereArgs: [id],
  );
}





}

