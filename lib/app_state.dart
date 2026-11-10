import 'package:flutter/material.dart';
import 'flutter_flow/flutter_flow_util.dart';
import 'dart:convert';

class FFAppState extends ChangeNotifier {
  static FFAppState _instance = FFAppState._internal();

  factory FFAppState() {
    return _instance;
  }

  FFAppState._internal();

  static void reset() {
    _instance = FFAppState._internal();
  }

  Future initializePersistedState() async {}

  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }

  List<dynamic> _listaMensagens = [jsonDecode('{}')];
  List<dynamic> get listaMensagens => _listaMensagens;
  set listaMensagens(List<dynamic> value) {
    _listaMensagens = value;
  }

  void addToListaMensagens(dynamic value) {
    listaMensagens.add(value);
  }

  void removeFromListaMensagens(dynamic value) {
    listaMensagens.remove(value);
  }

  void removeAtIndexFromListaMensagens(int index) {
    listaMensagens.removeAt(index);
  }

  void updateListaMensagensAtIndex(
    int index,
    dynamic Function(dynamic) updateFn,
  ) {
    listaMensagens[index] = updateFn(_listaMensagens[index]);
  }

  void insertAtIndexInListaMensagens(int index, dynamic value) {
    listaMensagens.insert(index, value);
  }
}
