import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share/share.dart';
import 'package:url_launcher/url_launcher.dart';

import 'home.dart';
import '../models/data.dart';
import '../models/entry.dart';
import '../models/nav.dart';

void _launchURL(String url) async {
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw Exception('Could not launch $url');
  }
}

Future<bool> _checkPermission() async {
  var status = await Permission.storage.status;
  if (status.isUndetermined) {
    await Permission.storage.request();
    status = await Permission.storage.status;
  }
  if (status.isGranted) {
    return true;
  }
  return false;
}

Future<String> _downloadURL(String url) async {
  String fileName = url.split('/').last;
  String downloadPath = '/storage/emulated/0/Download';

  // Get permission and download file
  final Future<bool> permissionReadyFut = _checkPermission();
  final Future<http.Response> responseFut = http.get(url);

  // Get download path
  final bool permissionReady = await permissionReadyFut;
  if (!permissionReady ||
      FileSystemEntity.typeSync(downloadPath) ==
          FileSystemEntityType.notFound) {
    downloadPath = (await getExternalStorageDirectory()).path;
  }

  // Get absolute file path. If a file with the same name exists, prepend the date.
  String filePath = '$downloadPath${Platform.pathSeparator}$fileName';
  if (FileSystemEntity.typeSync(filePath) != FileSystemEntityType.notFound) {
    final String now = '${DateTime.now().toString().substring(0, 19)}';
    filePath = '$downloadPath${Platform.pathSeparator}$now - $fileName';
  }
  final File file = File(filePath);

  // Save the file
  final http.Response response = await responseFut;
  await file.writeAsBytes(response.bodyBytes);
  return filePath;
}

Future<void> _handleURL(String url, BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      // The dialogContext allows using a SnackBar without the 'Scaffold.of()
      // called with a context that does not contain a Scaffold.' error.
      final String fileName = url.split('/').last;
      return AlertDialog(
        content: SingleChildScrollView(
          child: Text('Save on device or open in browser?\n\nFile: $fileName'),
        ),
        actions: <Widget>[
          FlatButton(
            child: Text('Save'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              Scaffold.of(context).showSnackBar(SnackBar(
                content: Text('Downloading file...'),
                duration: Duration(seconds: 60),
              ));
              final String filePath = await _downloadURL(url);
              Scaffold.of(context).hideCurrentSnackBar();
              Scaffold.of(context).showSnackBar(
                  SnackBar(content: Text('File saved in $filePath')));
            },
          ),
          FlatButton(
            child: Text('Open'),
            onPressed: () {
              _launchURL(url);
              Navigator.of(dialogContext).pop();
            },
          ),
        ],
      );
    },
  );
}

class MyEntryHeader extends StatelessWidget {
  MyEntryHeader({Key key, @required this.entry}) : super(key: key);
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            entry.title,
            textScaleFactor: 1.25,
            style: TextStyle(
              color: Theme.of(context).textTheme.headline6.color,
              fontWeight: Theme.of(context).textTheme.headline6.fontWeight,
            ),
          ),
          Divider(
            thickness: 1.0,
            color: Theme.of(context).textTheme.headline6.color,
          ),
          RichText(
            textScaleFactor: 0.75,
            text: TextSpan(
              style:
                  TextStyle(color: Theme.of(context).textTheme.subtitle2.color),
              children: <TextSpan>[
                TextSpan(text: 'by '),
                TextSpan(
                    text: entry.author,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: ', ' + Uri.parse(entry.url).host)
              ],
            ),
          ),
          Text(
            DateFormat.yMEd()
                .add_jm()
                .format(DateTime.parse(entry.publishedAt)),
            textScaleFactor: 0.75,
          ),
        ],
      ),
    );
  }
}

class MyEntryBody extends StatelessWidget {
  MyEntryBody({Key key, @required this.entry}) : super(key: key);
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            MyEntryHeader(entry: entry),
            Html(
              data: entry.content,
              onLinkTap: (url) async {
                // Suggest to download most common files
                final re = RegExp(r'\.('
                    r'7z|apk|avi|csv|doc|docx|flv|gif|h264|jpeg|jpg|mkv|mov|'
                    r'mp3|mp4|mpeg|mpg|odp|ods|odt|ogg|pdf|png|pps|ppt|pptx|'
                    r'psd|rtf|svg|tex|txt|webm|webp|xls|xlsx|zip'
                    r')$');
                if (re.hasMatch(url.toLowerCase())) {
                  return _handleURL(url, context);
                } else {
                  _launchURL(url);
                }
              },
              onImageTap: (url) async {
                // Suggest to download images
                return _handleURL(url, context);
              },
            ),
          ],
        ),
      ),
      onHorizontalDragEnd: (details) {
        // We need to filter entries from the complete list and not from the entries available in
        // the ListView.builder since the builder usually has a subset of entries (the ones
        // displayed).
        Entry nextEntry;
        final data = Provider.of<Data>(context, listen: false);
        final nav = Provider.of<Nav>(context, listen: false);
        final entries = filterEntries(data, nav);
        final index = entries.indexOf(entry);
        if (details.velocity.pixelsPerSecond.dx < 0 &&
            index < entries.length - 1) {
          nextEntry = entries[index + 1];
        } else if (details.velocity.pixelsPerSecond.dx > 0 && index > 0) {
          nextEntry = entries[index - 1];
        }
        if (nextEntry != null) {
          Navigator.pushReplacementNamed(
            context,
            '/entry',
            arguments: nextEntry,
          );
          final List<int> entryIds = [nextEntry.id];
          data.read(entryIds);
        }
      },
    );
  }
}

class MyEntryBottom extends StatelessWidget {
  MyEntryBottom({Key key, @required this.entry}) : super(key: key);
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: CircularNotchedRectangle(),
      child: Row(
        children: <Widget>[
          Spacer(),
          IconButton(
              icon: Icon(Icons.share),
              onPressed: () {
                // The box is necessary for iPads
                final RenderBox box = context.findRenderObject();
                Share.share(entry.url,
                    subject: entry.title,
                    sharePositionOrigin:
                        box.localToGlobal(Offset.zero) & box.size);
              }),
          Consumer<Data>(
            builder: (context, data, child) {
              return IconButton(
                icon: entry.starred
                    ? Icon(
                        Icons.star,
                        color: Colors.amber,
                      )
                    : Icon(Icons.star_border),
                onPressed: () => data.toggleStar(entry.id),
              );
            },
          ),
          Consumer<Data>(
            builder: (context, data, child) {
              return IconButton(
                icon: Icon(entry.status == 'read'
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () => data.toggleRead(entry.id),
              );
            },
          ),
          Spacer(),
        ],
      ),
    );
  }
}

class MyEntry extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Entry entry = ModalRoute.of(context).settings.arguments;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          entry.feed.title,
        ),
      ),
      body: MyEntryBody(entry: entry),
      bottomNavigationBar: MyEntryBottom(entry: entry),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.open_in_browser),
        onPressed: () => _launchURL(entry.url),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}
