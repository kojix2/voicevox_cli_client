
# VOICEVOX CLI Client

[VOICEVOX ENGINE](https://github.com/VOICEVOX/voicevox_engine)用のコマンドラインツールです。


# 機能

VOICEVOX ENGINEを利用して、テキストを音声ファイルにすることができます。

テキスト内にある空行を区切りとして、別々の音声ファイルに保存されます。一つの音声ファイルにまとめて出力することも可能です。

また、テキスト内の文章の先頭に決まった書式で記述することで、その部分以降の読み上げパラメータ(音声種別や速度など)を変更することができます。

複数のVOICEVOX ENGINEを設定することで、並列で音声変換が実行できます。

VOICEVOX ENGINEのユーザ辞書に対し、単語の追加、編集、削除、ファイルからの一括登録などができます。


# 動作要件

Rocky Linux 8.5で、ruby 2.5.9を使用して作成・動作チェックしていますが、Linuxでrubyが実行できる環境であれば動くと思います。

VOICEVOX ENGINEは別途用意して起動してください。(バージョン 0.11.3 で動作チェックしています)


# インストール、使用準備

ファイル一式を展開して設置してください。


`etc/config.rb` が設定ファイルです。ファイルを編集し、
```
VOICEVOX_ENGINE = [ "192.168.0.11:50021" ]
```
のように、VOICEVOX ENGINEを起動しているIPアドレスorホスト名と、ポート番号に修正してください。

複数のVOICEVOX ENGINEを使用する場合は、
```
VOICEVOX_ENGINE = [ "192.168.0.11:50021", "192.168.0.12:50021" ]
```
のように、複数記述してください。

設定後に
```bash
$ vvtts --check
```
コマンドで、設定したVOICEVOX ENGINEが動作しているかどうか確認できます。

アンインストールする場合は、設置・作成したファイルを全て削除してください。


# 使い方

## テキストを音声ファイルに変換

テキストを音声ファイルに変換する
```bash
$ vvtts -s 2 "音声ファイルに変換したいテキストをここに入力してください"
```

テキストが記述されたファイルを指定し、音声ファイルに変換する
```bash
$ vvtts -s 3 -f text.txt -1
```
空行で別々のファイルに分割せずに、1つのファイルに保存したい場合は `-1` オプションも指定してください。

他のコマンドが出力したメッセージを音声ファイルに変換する
```bash
$ date | vvtts
```

その他、使用できるオプションを確認する
```bash
$ vvtts --help
```

## テキストを読み上げ

`aplay -D sysdefault output.wav` コマンドで音声ファイルを再生できる環境であれば、`-p` オプションを付けることで直接読み上げます。
```bash
$ vvtts -p -s 8 "読み上げたいテキストをここに入力してください"
```
`aplay` コマンドで `sysdefault` 以外のデバイスを使用したい場合は、`etc/config.rb` の `APLAY_VVTTS_DEVICE` の設定値を変更してください。

一般ユーザで読み上げたい場合、ユーザが `audio` グループに所属している必要があります。


## テキスト内で音声種別や速度などを変更する

以下のように特定の書式を文章の先頭に記述して、
```
#{s9}こんにちは
#{s10,S1.5}こんにちは
```
変換を実行することで音声種別などのパラメータを途中から変更することができます。
```
$ vvtts -f text.txt
```

同様に以下のように記述可能です。複数のパラメータを変更したい場合は `#{s12,I1.5}` のようにカンマ区切りで記述できます。

| テキストに記述する文字 | 効果 |
| ---- | ---- |
| #{s12} | 音声種別変更。数字の代わりに「R」を記述するとランダムで選択されます |
| #{q5} | クエリ時の声の種別を変更 |
| #{m3,r0.5} | モーフィング先の声の種別と、モーフィングレートを変更 |
| #{S0.8} | スピードスケールを変更 |
| #{P-0.1} | ピッチスケールを変更 |
| #{I1.5} | イントネーションスケールを変更 |
| #{V1.2} | ボリュームスケールを変更 |

数字部分に設定したい値を記述します。数字の代わりに `X` を記述すると、デフォルト値に戻すことができます。


## 置換リスト

`etc/replace.list` が置換リストです。このリストに基づいて入力文字列の置換処理が行われます。

置換リストは、1行に1項目、置換前の文字列と置換後の文字列をタブ区切りで記述してください。`#` で始まる行はコメント行として無視されます。

置換前の文字列は正規表現で記述することができます。
```replace.list
さようなら      ごきげんよう
私|わたし       わたくし
[Pp]ython       パイソン
```

置換リストによる置換だけでなく、全角英数字を半角英数字に変換、スペースを削除などの処理が行われた後、VOICEVOX ENGINEに渡されます。入力した文字列をそのままVOICEVOX ENGINEに渡したい場合は `--raw` オプションを指定してください。


## 読み方&アクセント辞書

`vvdict` コマンドで、VOICEVOX ENGINEに読み方&アクセント辞書を登録できます。

単語追加 - `単語` `読み方(カタカナ)` `アクセント核位置` を順に指定してください
```
$ vvdict add ruby ルビー 1
```

単語修正 - `単語` `読み方(カタカナ)` `アクセント核位置` を順に指定してください
```
$ vvdict mod ruby ルビー 0
```

単語削除 - `単語` を指定してください
```
$ vvdict del ruby
```

単語をすべて削除
```
$ vvdict deleteall
```

登録済みの単語表示 (この出力をリダイレクトでファイル保存すれば、一括登録リストとして使えます)
```
$ vvdict show
```

単語を一括登録リストからまとめて登録 (一括登録リストは `単語` `読み方(カタカナ)` `アクセント核位置` をタブ区切りで1行に1単語づつ記 述)
```
$ vvdict listadd list.txt
```

単語をすべて削除したうえで、一括登録リストからまとめて登録
```
$ vvdict rereg list.txt
```


# その他

チャットの読み上げなどで利用できるよう、入力されたテキストを順番に読み上げる簡易ツールを作成しています。`vvtts` コマンドで読み上げを行う場合と同じく、`aplay -D sysdefault <音声ファイル>.wav` で音声を再生できる環境が必要です。

起動
```bash
$ sbin/seqreadd start
```

起動すると `seqread.rb` が実行されます。`seqread.rb` 実行中は `seqread` コマンドで読み上げ文字列の登録ができます。(`var/run/seqread.sock` に対する書き込み権限が必要なことに注意ください)

読み上げ文字列は、コマンドオプションとして指定するか、パイプで渡します。
```
$ seqread "読み上げたいメッセージ"
$ cat text.txt | seqread
```

登録された文字列は、`vvtts` コマンドを用いて登録された順に音声変換後再生されます。再生中にも並行して音声変換が実行されるようになっています。

チャットボットで使用される[Hubot](https://hubot.github.com/)で `seqread` コマンドを呼び出すためのサンプルスクリプトが `etc/hubot_script/yomiage.js` にあります。


# ライセンス

VOICEVOX_CLI_Client is under [MIT license](https://en.wikipedia.org/wiki/MIT_License).

