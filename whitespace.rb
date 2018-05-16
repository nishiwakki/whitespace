require 'strscan'
require 'kconv'

class Whitespace

  @code # ソースコードを保持
  @result # 上記3つが格納された配列（eval関数に渡される）
  @@results # resultを格納する配列
  @stack # スタックに見立てた配列
  @heap # ヒープアクセス用の配列
  @labels # ラベル用の配列
  @routine # サブルーチン内でサブルーチンを呼びだした用の配列
  @pc # フロー制御用のプログラムカウンター

  def initialize
    @@results = []
    @stack = []
    @heap  = {}
    @labels = {}
    @routine = {}
    @pc = 0

    begin
      file = open(ARGV[0])
      # なぜかtxtで読み込むと、"\t"が"\\t"、"\n"が”\\n”と表示されるため
      @fileread = file.read.chomp!.gsub(/\\t|\\n/, "\\t" => "\t", "\\n" => "\n")
      file.close()
    rescue Errno::ENOENT # 指定されたファイルが見つからないとき
      p 'cannot find designated file.'
      exit # 終了
    end
  end

  def tokenize
    scanner = StringScanner.new(@fileread)
    while !scanner.eos?
      @result = Array.new # @result配列は、各処理ごとで書き換えるため、initialize内では初期化しない
      prmts = "" #prmtsが存在しないコマンドも存在するため、毎度空白にしている
      unless imp = scanner.scan(/ |\n|\t[ \n\t]/)
        raise Exception, 'missing imp'
      end
      case imp # imp:切り出し用, imps:@result配列に格納用

      # スタック操作
      when " "
        unless cmnd = scanner.scan(/ |\n[ \n\t]/)
          raise Exception, 'missing Stack Command'
        end
        imps = :Stack

        case cmnd
        when " "
          cmnds = :Push # 値をスタックに積む
          unless prmt = scanner.scan(/[ \t]{2,}\n/)
            raise Exception, 'missing push Parameter'
          end
          prmts = prmt
        when "\n "
          cmnds = :Duplicate # スタックの一番上の値を複製
        when "\n\t"
          cmnds = :Swap # スタックの上から2つの値を入れ替える
        when "\n\n"
          cmnds = :Discard # スタックの一番上の値を取り除く
        end

      # 算術演算
      when "\t "
        unless cmnd = scanner.scan(/ [ \n\t]|\t[ \t]/)
          raise Exception, 'missing Arithmetic Command'
        end
        imps = :Arithmetic

        case cmnd
        when "  "
          cmnds = :Add # 足し算
        when " \t"
          cmnds = :Subt # 引き算
        when " \n"
          cmnds = :Multi # 掛け算
        when "\t "
          cmnds = :IntDiv # 割り算
        when "\t\t"
          cmnds = :Mod # 割り算のあまり
        end

      # ヒープアクセス
      when "\t\t"
        unless cmnd = scanner.scan(/ |\t/)
          raise Exception, 'missing Heap Access Command'
        end
        imps = :Heap
        case cmnd
        when " "
          cmnds = :Store # ヒープへの書き込み
        when "\t"
          cmnds = :Retrieve # ヒープからの読み込み
        end

      # フロー制御
      when "\n"
        unless cmnd = scanner.scan(/ [ \t\n]|\t[ \t\n]|\n[\n]/)
          raise Exception, 'missing Flow Control Command'
        end
        imps = :Flow

        case cmnd
        when "  "
          cmnds = :Mark # ラベルの設定
          unless prmt = scanner.scan(/[ \t]+\n/)
            raise Exception, 'missing Mark Parameter'
          end
          prmts = prmt
        when " \t"
          cmnds = :CallSrtn # サブルーチンの呼出し
        when " \n"
          cmnds = :Jump # 無条件ジャンプ
          unless prmt = scanner.scan(/[ \t]+\n/) # namespaceが1つだけなので、ラベルが必ず一意
            raise Exception, 'missing Jump Parameter'
          end
          prmts = prmt
        when "\t "
          cmnds = :JumpZero # スタックの一番上の値が0ならジャンプ
          unless prmt = scanner.scan(/[ \t]+\n/)
            raise Exception, 'missing JumpZero Parameter'
          end
          prmts = prmt
        when "\t\t"
          cmnds = :JumpNega # スタックの一番上の値が負ならジャンプ
          unless prmt = scanner.scan(/[ \t]+\n/)
            raise Exception, 'missing JumpNega Parameter'
          end
          prmts = prmt
        when "\t\n"
          cmnds = :EndSrtn # サブルーチンを抜ける
        when "\n\n"
          cmnds = :End # プログラムの実行終了
        end

    # 入力/出力
    when "\t\n"
        unless cmnd = scanner.scan(/ [ \t]|\t[ \t]/)
          raise Exception, 'missing I/0 Command'
        end
        imps = :IO

        case cmnd
        when "  "
          cmnds = :OutCha # 文字の出力(ASCII)
        when " \t"
          cmnds = :OutNum # 数値の出力
        when "\t "
          cmnds = :InCha # 文字入力
        when "\t\t"
          cmnds = :InNum # 数値入力
        end

      end

      @result << imps << cmnds << prmts # @result[0, 1, 2]
      @@results << @result

      @pc = @pc + 1 # ここでのプログラムカウンタは、処理数を数える役割を持っている
    end
  end

  # ラベルの貼り付けはプログラムの処理前に行わないと、
  # ラベルジャンプをする前にそのラベル設定をする必要が出てしまう
  def setLabel
    pc = 0
    @@results.each{|array|
      if array[1] == :Mark # array[1]にはcmndsが代入済み
        @labels[array[2]] = pc # array[2]にはprmtsが代入済み
      end
      pc = pc + 1
    }
  end

  def eval
    taskNum = @pc # 処理の数は現在pcに入っている数-1
    @pc = 0
    while @pc < taskNum # プログラムカウンタが処理の全体数より大きくなるまで
      case @@results[@pc][1] # cmndsが何かでcase文
      # スタック操作
      when :Push
        @stack.push(self.numChanger(@@results[@pc][2])) # 文字列型から数値型へ変化させる
      when :Duplicate
        @stack.push(@stack.last)
      when :Swap
        x = @stack.pop
        y = @stack.pop
        @stack.push(x)
        @stack.push(y)
      when :Discard
        @stack.pop

      # 算術演算
      when :Add
        x = @stack.pop
        y = @stack.pop
        @stack.push(y + x)
      when :Subt
        x = @stack.pop
        y = @stack.pop
        @stack.push(y - x)
      when :Multi
        x = @stack.pop
        y = @stack.pop
        @stack.push(y * x)
      when :IntDiv
        x = @stack.pop
        y = @stack.pop
        @stack.push(y / x)
      when :Mod
        x = @stack.pop
        y = @stack.pop
        @stack.push(y % x)

      # ヒープアクセス
      when :Store
        value = @stack.pop # 書き込む値
        address = @stack.pop # 書き込みたい位置
        @heap[address] = value
      when :Retrieve
        address = @stack.pop # 読み込みたいアドレス
        value = @heap[address]
        if value.nil? # 参照したaddressのvalueがnilだった場合
          raise Exception, "StackError"
        end
        @stack.push(value)

      # フロー制御
      when :Mark
        # ラベルマークは、プログラム実行前に全て記録するためここでは行わない setLabelにて
      when :CallSrtn
        @routine.push(@pc)
        jumping(@@results[@pc][2]) # prmtsで指定したラベルにジャンプ
      when :Jump
        jumping(@@results[@pc][2])
      when :JumpZero
        if @stack.pop == 0 # ポップした値が0なら
          jumping(@@results[@pc][2])
        end
      when :JumpNega
        if @stack.pop < 0 # ポップした値が負なら
          jumping(@@results[@pc][2])
        end
      when :EndSrtn
        @pc = @routine.pop
        if @pc.nil?
          raise Exception, "cannot end subroutine."
        end
      when :End
        exit

      # 入出力
      when :OutCha
        print @stack.pop.chr # ポップした数値のASCIIコードに変換
      when :OutNum
        print @stack.pop
      when :InCha
        address = @stack.pop # ポップした値のアドレスに
        @heap[address] = STDIN.gets.chomp! # 文字を入力（語尾に改行がつくので排除）
      when :InNum
        address = @stack.pop # ポップした値のアドレスに
        @heap[address] = STDIN.gets.to_i # 数値を入力
      end

      @pc = @pc + 1 # プログラムカウンタの値を1つ増やす（処理を進める）

      # きちんと処理が行われているのかテスト用
      #print "stack: "
      #p @stack
      #print "heap:  "
      #p @heap
      #print "labels:"
      #p @labels
      #print "pc:    "
      #p @pc
    end
  end

  def jumping(index) # 引数の位置にジャンプするメソッド。フロー制御で頻繁利用
   @pc = @labels[index]
   if @pc.nil?
     raise Exception, "cannnot find designated jumping point."
   end
  end

  def numChanger(str) # 主にスタック操作Pushで用いられる。[s][t][n]羅列から値に変換
    number = ""
    str =~ /([ \t])([ \t]+)\n/ #正規表現を詳細に切り出している。$1が正負判別, $2が整数
    scan = StringScanner.new($2)
    while !scan.eos?
      num = scan.scan(/ |\t/) # spaceで 0 , tabで 1 を表す
      case num
      when " "
        number += "0"
      when "\t"
        number += "1"
      end
    end
    if $1 == " " then # 正の時
      return number.to_i(2) # 文字列を数値に変換
    else # 負の時
      return -number.to_i(2)
    end
  end

end

ws = Whitespace.new
ws.tokenize # 字句解析
ws.setLabel # ラベルセット
ws.eval     # 解釈実行
