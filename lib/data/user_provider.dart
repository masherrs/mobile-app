import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:podcast_app/components/card_continuelistening.dart';
import 'package:podcast_app/models/callback_model.dart';
import 'package:podcast_app/models/episode_model.dart';
import 'package:podcast_app/models/history_search_model.dart';
import 'package:podcast_app/models/topic_model.dart';
import 'package:podcast_app/models/user_model.dart';

class UserProvider with ChangeNotifier, DiagnosticableTreeMixin {
  //region state
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;

  String _completeProfilePictureUrl = "";

  String get completeProfilePictureUrl => _completeProfilePictureUrl;

  UserModel _user = UserModel();

  UserModel get user => _user;

  List<TopicModel> _myTopics = [];

  List<TopicModel> get myTopics => _myTopics;

  List<HistorySearchModel> _historySearch = [];

  List<HistorySearchModel> get historySearch => _historySearch;

  List<UserModel> _myProfile = [];

  List<UserModel> get myProfile => _myProfile;

  List<EpisodeModel> _listeningPodcast = [];

  List<EpisodeModel> get listeningPodcast => _listeningPodcast;

  //end region

  FirebaseFirestore db = FirebaseFirestore.instance;

  FirebaseAuth auth = FirebaseAuth.instance;

  FirebaseStorage storage = FirebaseStorage.instance;

  //region
  Future<Response> signOut() async {
    try {
      final credential = await auth.signOut();
      return Future.value(Response.Ok(message: ""));
    } on FirebaseAuthException catch (e) {
      return Response.Failed(message: e.code);
    }
  }

  Future<Response> getListeningPodcast() async {
    final userId = await auth.currentUser;
    if (userId == null) {
      return Future.value(Response.Failed(message: ""));
    }
    final data = await db
        .collection("USER")
        .doc(userId.uid)
        .collection("LISTENING")
        .withConverter(
            fromFirestore: EpisodeModel.fromFirestore,
            toFirestore: (l, _) => l.toFirestore())
        .get();

    //convert in array
    final convertData = data.docs.map((user) => user.data());

    //notify apps the data has changed
    _listeningPodcast.addAll(convertData);
    notifyListeners();

    return Future.value(Response.Ok(message: ""));
  }

  Future<Response> getMyprofile() async {
    final userId = await auth.currentUser;
    if (userId == null) {
      return Future.value(Response.Failed(message: ""));
    }
    final data = await db
        .collection("USER")
        .doc(userId.uid)
        .withConverter(
            fromFirestore: UserModel.fromFirestore,
            toFirestore: (mp, _) => mp.toFirestore())
        .get();

    if (data.exists) {
      final myProfileResult = data.data();
      if (myProfileResult != null) {
        notifyListeners();
      }
    }
    return Future.value(Response.Ok(message: ""));
  }

  //https://stackoverflow.com/questions/65221515/flutter-firebase-logged-in-user-returns-a-null-currentuser-after-sign-in
  Future<bool> checkIsLoggedIn() async {
    _isLoggedIn = auth.currentUser != null;
    print(auth.currentUser.toString());
    return _isLoggedIn;
  }

  Future<Response> getHistorySearch() async {
    final userId = await auth.currentUser;
    if (userId == null) {
      return Future.value(Response.Failed(message: ""));
    }

    final data = await db
        .collection("USER")
        .doc(userId.uid)
        .collection("HISTORY SEARCH")
        .withConverter(
            fromFirestore: HistorySearchModel.fromFirestore,
            toFirestore: (hs, _) => hs.toFirestore())
        .get();

    //convert in array [HistorySearchModel]
    final convertData = data.docs.map((hs) => hs.data());

    //notify apps the data has changed
    _historySearch.addAll(convertData);
    notifyListeners();

    //always return success
    return Future.value(Response.Ok(message: ""));
  }

  Future<Response> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      //sign in with email and password
      final credential = await auth.signInWithEmailAndPassword(
          email: email, password: password);

      //if user empty sign in should be failed
      if (credential.user == null) {
        return Future.value(Response.Failed(message: 'Login Gagal'));
      }

      //check if profile already exist
      final alreadyCompleteProfile = await db
          .collection('USER')
          .doc(credential.user!.uid)
          .withConverter(
              fromFirestore: UserModel.fromFirestore,
              toFirestore: (user, _) => user.toFirestore())
          .get();

      //tell app that user neet complete profile after loggedin
      if (!alreadyCompleteProfile.exists) {
        return Future.value(
            Response.OkCompleteProfile(message: 'Login Berhasil'));
      }

      return Future.value(Response.Ok(message: ""));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return Future.value(
            Response.Failed(message: 'No User found for that email.'));
      } else if (e.code == 'wrong-password') {
        Response.Failed(message: 'password lu salah cok');
      }
      return Future.value(Response.Failed(message: e.code));
    }
  }

  Future<Response> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount googleUser = await GoogleSignIn().signIn();

      // Obtain the auth details from the request
      final GoogleSignInAuthentication? googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth?.accessToken,
        idToken: googleAuth?.idToken,
      );

      final user = await auth.signInWithCredential(credential);

      //if user empty sign in should be failed
      if (user.user == null) {
        return Future.value(Response.Failed(message: 'Login Gagal'));
      }

      //check if profile already exist
      final alreadyCompleteProfile = await db
          .collection('USER')
          .doc(user.user!.uid)
          .withConverter(
              fromFirestore: UserModel.fromFirestore,
              toFirestore: (user, _) => user.toFirestore())
          .get();

      //tell app that user neet complete profile after loggedin
      if (!alreadyCompleteProfile.exists) {
        return Future.value(
            Response.OkCompleteProfile(message: 'Login Berhasil'));
      }

      return Future.value(Response.Ok(message: ""));
    } on FirebaseAuthException catch (e) {
      return Future.value(Response.Failed(message: e.code));
    }
  }

  Future<Response> registerWithEmailAndPassword(
      String email, String password, String name) async {

    try {
      final credential = await auth.createUserWithEmailAndPassword(
          email: email, password: password);

      final user = UserModel(name: name, email: email, level: "USER");
      await db
          .collection('USER')
          .doc(credential.user!.uid)
          .set(user.toFirestore());
      return Future.value(
          Response.OkCompleteProfile(message: 'Daftar Berhasil'));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        return Future.value(
            Response.Failed(message: 'The password provided is too weak.'));
      } else if (e.code == 'email-already-in-use') {
        Response.Failed(message: 'The account already exists for that email.');
      }
      return Future.value(Response.Failed(message: e.code));
    }
  }

  Future<Response> uploadProfilePicture(File file) async {
    //get userUid for name image ex: userUid.jpg
    var currentUser = auth.currentUser;

    final userId =
        currentUser?.uid ?? DateTime.now().microsecondsSinceEpoch.toString();
    //create folder and location file
    final profileRef = storage.ref().child("USER_PROFILE").child("$userId.jpg");

    try {
      //start uplaoding
      await profileRef.putFile(file);

      //save upload url temporary
      _completeProfilePictureUrl = await profileRef.getDownloadURL();
      notifyListeners();
      return Response.OkWithArg(message: "Gambar profile berhasil di upload",arg: {
        "url":_completeProfilePictureUrl
      });
    } on FirebaseException catch (e) {
      return Response.Failed(message: e.message.toString());
    }
  }

  Future<Response> completeProfile(UserModel arg) async {
    var currentUser = auth.currentUser;
    final userId = currentUser?.uid;

    await db
        .collection("USER")
        .doc(userId)
        .withConverter(
            fromFirestore: UserModel.fromFirestore,
            toFirestore: (user, _) => user.toFirestore())
        .set(arg);
    //TODO:: complete profile
    return Future.value(Response.Ok(message: "Profile berhasil disimpan"));
  }

  Future<Response> saveMyTopic(List<TopicModel> topics) async {
    try {
      final batch = db.batch();
      var currentUser = auth.currentUser;

      //looping topicnya
      myTopics.forEach((myTopics) {
        final doc = db
            .collection("TOPICS")
            .doc(currentUser!.uid)
            .collection("TOPICS")
            .doc();
        batch.set(doc, myTopics.toFirestore());
      });

      //set value topic
      return Future.value(Response.Ok(message: ""));
    } on FirebaseException catch (e) {
      return Response.Failed(message: e.message.toString());
    }
  }

  Future<Response> saveTopicUser(List<TopicModel> topics) async {
    try {
      //buat batch transaction contract
      final batch = db.batch();
      var currentUser = auth.currentUser;

      //looping topicnya
      topics.forEach((topic) {
        //cari datanya mau di taro di mana dan geneeratee unique id
        final doc = db
            .collection("USER")
            .doc(currentUser!.uid)
            .collection("USER")
            .doc();
        batch.set(doc, topic.toFirestore());
      });

      // Set value topic

      return Future.value(Response.Ok(message: ""));
    } on FirebaseException catch (e) {
      return Response.Failed(message: e.message.toString());
    }
  }

  Future<Response> continueListening() async {
    try {
      final data = await db
          .collection("USER")
          .doc(auth.currentUser!.uid)
          .collection("LISTENING")
          .withConverter(
              fromFirestore: EpisodeModel.fromFirestore,
              toFirestore: (listening, _) => listening.toFirestore())
          .get();
      _listeningPodcast.addAll(data.docs.map((value) => value.data()));
      notifyListeners();
      return Future.value(Response.Ok(message: ""));
    } on FirebaseAuthException catch (e) {
      return Future.value(Response.Failed(message: e.code));
    }
  }
//end region
}
