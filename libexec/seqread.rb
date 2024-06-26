#!/usr/bin/env ruby

require 'socket'
require 'open3'
require 'fileutils'
require 'json'
require 'optparse'

# バージョン
VERSION="1.0.1"


#------
# 設定
#------

# データ受け取り用ソケットのパス
SOCKFILE = "#{__dir__}/../var/run/seqread.sock"

# vvttsコマンドのパス
VVTTSCMD = "#{__dir__}/../bin/vvtts"

# 設定ファイルを読み込む
if File.exist?("#{__dir__}/../etc/config.rb")
  require_relative '../etc/config.rb'
else
  STDOUT.print "設定ファイル \"#{__dir__}/../etc/config.rb\" が見つかりません"
  exit 1
end

# ../var/run ディレクトリがなければ作成
FileUtils.mkdir_p("#{__dir__}/../var/run") unless FileTest.exist?("#{__dir__}/../var/run")


#----------
# 関数定義
#----------

# デバッグメッセージを表示する関数
def debug_print(message)
  if @debug_flag == 1 then
    STDERR.print "Debug: #{message}\n"
  end
end

# 文字列を音声に変換するスレッドで実行される処理
def make_wavdata(jsondata)
  begin
    # JSONをハッシュに変換
    msgdata=JSON.parse(jsondata)
    # 投稿されたメッセージを取り出す
    msg_text = msgdata["message"]
    # 再生コマンドにパイプで音声データを渡して実行
    o, e, s = Open3.capture3("#{VVTTSCMD} --stdout", :stdin_data=>msg_text)
    # 標準出力のwavデータを返す
    return o
  # 何かエラーが発生したら
  rescue => e
    # エラーが発生したら nil を返す
    STDERR.print "テキスト音声変換スレッドでエラーが発生しました (e=\"#{e.message}\")\n"
    STDERR.print "VVTTSCMD=#{VVTTSCMD}\n"
    return nil
  end
end


# 音声データを再生するスレッドで実行される処理
def play_wav(play_command, wavdata)
  begin
    # aplayコマンドで再生する場合
    if play_command == "aplay" then
      play_cmd = "aplay -D #{APLAY_SEQREAD_DEVICE}"
    # sox(play)コマンドで再生する場合
    elsif play_command == "sox" then
      # 環境変数「AUDIODEV」で再生するデバイスを指定
      ENV['AUDIODEV'] = SOX_SEQREAD_DEVICE
      # 再生コマンド
      play_cmd = "play -"
    end
    # 再生コマンドにパイプで音声データを渡して実行
    Open3.capture3(play_cmd, :stdin_data=>wavdata)
  rescue => e
    # エラーが発生したら nil を返す
    STDERR.print "音声再生スレッドでエラーが発生しました (e=\"#{e.message}\")\n"
    return nil
  end
end


#----------
# 処理開始
#----------

# オプションの処理
opt = OptionParser.new
opt.on('--debug', 'デバッグメッセージを出力します') {|v| @debug_flag = 1 }
opt.on('--version', 'バージョンを出力します') {|v| print "#{VERSION}\n" ; exit }
opt.parse!(ARGV)

# データを受け取る用のソケットを作成して待ち受ける
unix_dgram = Socket.new(:UNIX, :DGRAM)
File.unlink(SOCKFILE) if File.exist? SOCKFILE
unix_dgram.bind Socket.sockaddr_un(SOCKFILE)
FileUtils.chmod(0600, SOCKFILE)

# データ(JSON)を格納する配列
json_array = Array.new

# 音声データを格納する配列
voice_array = Array.new

# データ読み出しスレッド変数を初期化
read_thread = nil

# 変換スレッド変数を初期化
conv_thread = nil

# 再生スレッド変数の初期化
play_thread = nil

#　PLAY_CMD に値「aplay」または「sox」が設定されていたらその値をセットする
if PLAY_CMD == "aplay" or PLAY_CMD == "sox" then
  play_command = PLAY_CMD
  debug_print("#{play_command}を使用して再生を実行します")
  # コマンドがあるかチェック
  if play_command == "aplay" then
    num = `which #{play_command} | wc -l 2>/dev/null`
    if num.to_i == 0 then
      STDERR.print "音声を再生するためのコマンド \"#{play_command}\" が見つからないため、再生できません\n"
      exit 1
    end
  elsif play_command == "sox" then
    num = `which play | wc -l 2>/dev/null`
    if num.to_i == 0 then
      STDERR.print "音声を再生するためのコマンド \"play(sox)\" が見つからないため、再生できません\n"
      exit 1
    end
  end
# PLAY_CMD の値が空だったり、正しくない場合は使えるコマンドがないか調べる
else
  debug_print("再生コマンドを検索します")
  # aplayコマンドがあるかチェック
  num = `which aplay | wc -l 2>/dev/null`
  # aplayコマンドが見つかった場合
  if num.to_i > 0 then
    debug_print("aplayコマンドが見つかりました")
    play_command = "aplay"
  # aplayコマンドが見つからない場合
  else
    # soxコマンドがあるかチェック
    num = `which play | wc -l 2>/dev/null`
    # soxコマンドが見つかった場合
    if num.to_i > 0 then
      debug_print("play(sox)コマンドが見つかりました")
      play_command = "sox"
    # soxコマンドも見つからない場合
    else
      STDERR.print "コマンド \"aplay\" か \"play(sox)\" がともに見つからないため、再生はできません\n"
      exit 1
    end
  end
end

# 無限ループで繰り返す
catch :loop do
  while true do

    # 1秒待つ
    sleep 1

    # データ読み出しスレッドが実行されていなかったら
    if read_thread.nil? then
      # 読み出しスレッドを実行
      read_thread = Thread.new { unix_dgram.recv(4096) }
      # デバッグ用
      debug_print("start read thread (J=#{json_array.length} V=#{voice_array.length})")
    # データ読み出しスレッドが終了していたら
    elsif read_thread.status == false then
      # 正常終了で戻り値があれば
      if (not read_thread.nil?) and (not read_thread.value.nil?) then
        # json_arrayに格納
        json_array << read_thread.value
      end
      # 読み出しスレッドを停止
      read_thread = nil
      # デバッグ用
      debug_print("stop read thread (J=#{json_array.length} V=#{voice_array.length})")
    end


    # 変換スレッドが実行されておらず、変換すべきテキストがあったら
    if conv_thread.nil? and json_array.length > 0 then
      # データを取り出して新たな変換スレッドを実行
      data = json_array.shift
      conv_thread = Thread.new { make_wavdata(data) }
      # デバッグ用
      debug_print("start conv thread (J=#{json_array.length} V=#{voice_array.length})")
    # 変換スレッドが終了していたら
    elsif (not conv_thread.nil?) and conv_thread.status == false then
      # 正常終了で戻り値があれば
      if (not conv_thread.value.nil?) then
        # voice_arrayに格納
        voice_array << conv_thread.value
      end
      # 変換スレッドを停止
      conv_thread = nil
      # デバッグ用
      debug_print("stop conv thread (J=#{json_array.length} V=#{voice_array.length})")
    end


    # 再生スレッドが実行されておらず、再生すべき音声があったら
    if play_thread.nil? and voice_array.length > 0 then
      # データを取り出して新たな変換スレッドを実行
      voicedata = voice_array.shift
      play_thread = Thread.new { play_wav(play_command, voicedata) }
      # デバッグ用
      debug_print("start new play thread (J=#{json_array.length} V=#{voice_array.length})")
    # 再生スレッドが終了していたら
    elsif (not play_thread.nil?) and play_thread.status == false then
      # 再生スレッドを停止
      play_thread = nil
      # デバッグ用
      debug_print("stop play thread (J=#{json_array.length} V=#{voice_array.length})")
    end

    # メモリ開放
    GC.start

  end
end
