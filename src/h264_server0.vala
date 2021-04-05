using Gst;

        const string localhost = "10.0.0.5";


         MainLoop loop;
         uint8 dataH264[10000];
         Gst.Buffer *buffer;
         Gst.ClockTime timestamp = 0;
         bool want = false;
         File file;
         size_t size;
         FileInputStream is;
         GLib.Socket socket;
         GLib.Socket connection;

        private void prepare_buffer(Gst.App.Src appsrc){
          //stdout.printf("prepare_buffer");
          if(!want){
            //stdout.printf("Don't need");
            return;}
          want = false;
          size = is.read(dataH264);
          uint8 len[10];
          //connection.receive(len);
          //connection.receive(dataH264);
          //Posix.memcpy(&size,len,sizeof(size_t));
          //stdout.printf ("Size: %" + size_t.FORMAT + "\n", size);

          buffer = Gst.Buffer.new_wrapped_full(0,dataH264,0,size,null);

          buffer->pts = timestamp;
          buffer->duration = Gst.Util.uint64_scale_int(1,Gst.SECOND,30);

          timestamp += buffer->duration;
          appsrc.push_buffer(buffer);
        }
        private void OnNeedData(uint length)
        {
          want = true;
        }

        private void OnEnoughData()
        {
            want = false;
            stdout.printf("OnEnoughData\n");
        }
        public static int main (string[] args) {

                Gst.init (ref args);
              //  Gtk.init (ref args);
                stdout.puts("----------video_server--------------\n");
                loop = new MainLoop();
                Gst.Pipeline pipeline;
                Gst.App.Src appsrc;

                file = File.new_for_path ("out.h264");
                is = file.read ();

                InetAddress server_address = new InetAddress.from_string (localhost);
                InetSocketAddress address = new InetSocketAddress (server_address, 5558);
                socket = new GLib.Socket (GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
                assert (socket != null);
                socket.bind (address, true);
                socket.set_listen_backlog (10);
                socket.listen ();
                connection = socket.accept ();

                pipeline = (Gst.Pipeline) Gst.parse_launch("appsrc name=mysource ! video/x-h264 ! h264parse ! avdec_h264 ! videoconvert ! videorate ! video/x-raw,framerate=30/1 ! autovideosink");
                appsrc = (Gst.App.Src)pipeline.get_by_name("mysource");
                appsrc.set_emit_signals(true);
                appsrc.set_stream_type(Gst.App.StreamType.STREAM);

                stdout.printf("Pipeline and appsrc initialized\n");

                //GLib.Value val_format = new GLib.Value(typeof(string));
                GLib.Value val_width = new GLib.Value(typeof(int));
                GLib.Value val_height = new GLib.Value(typeof(int));
                GLib.Value val_framerate = new GLib.Value(typeof(Gst.Fraction));
                //val_format.set_string("RGB16");
                val_width.set_int(800);
                val_height.set_int(480);
                Gst.Value.set_fraction(val_framerate,25,1);
                Gst.Caps cap = new Gst.Caps.empty_simple("video/x-h264");
                //cap.set_value("format",val_format);
                cap.set_value("width",val_width);
                cap.set_value("height",val_height);
                cap.set_value("framerate",val_framerate);
                appsrc.set_caps(cap);

              //appsrc.set("format", Gst.Format.TIME,"stream-type",0,"is-live",true);
                appsrc.need_data.connect(OnNeedData);
                appsrc.enough_data.connect(OnEnoughData);

                stdout.printf("play\n");
                pipeline.set_state(Gst.State.PLAYING);
                while (true) {
                  prepare_buffer(appsrc);
                }
                loop.run();
                return 0;
        }
