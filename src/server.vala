
	using GLib;
	using Gst;
	const uint16 media_port=5557;
	const uint headerLen = 12;
	const string localhost = "10.0.0.5";
public class Response:GLib.Object{
	public string resp;
	public size_t len;
	public 	Response(string resp,size_t len){
		this.resp = resp;
		this.len = len;
	}
}

public class MyServer : GLib.Object {

	private bool wait = true;
	private bool start = false;
	public MyServer () {

	}
	public Response jpeg_receive(GLib.Socket conn,uint8[] buffer){//Принимает JPEG файл, определяя заголовок

		uchar ret[headerLen];
		string result = "ok";
		size_t len = conn.receive(buffer);
		for(uint j=0;j<headerLen;j=j+1){
				ret[j]=buffer[j];
		}
		if((buffer[16]==0xff)&&(buffer[17]==0xd8)) result = "jpeg_header"; //Заголовок JPEG Файла
		if((buffer[len-1]==0xff)&&(buffer[len]==0xd9)) result = "jpeg_end";
		if((ret[0]==0x8)&&(ret[1]==0x06)) result = "header";//Заголовок протокола видеорегистратора
		if ((ret[0]==0x8)&&(ret[1]==0x16)) result = "error";
		Response r = new Response(result,len);
		return r;
	}
	public Response h264_receive(GLib.Socket conn,uint8[] buffer){//Принимает H264 Data, определяя заголовок

		uchar ret[headerLen];
		size_t len = conn.receive(buffer);
		for(uint j=0;j<headerLen;j=j+1){
				ret[j]=buffer[j];
		}
		string result = "ok";
		if((ret[0]==0x8)&&(ret[1]==0x2)) result = "header";//Заголовок протокола видеорегистратора
		Response r = new Response(result,len);
		return r;
	}
	public int json_send(string message,GLib.Socket conn){//Создает заголовок протокола и отправляет вместе с message
		uint8 header[headerLen];
		header = {0x08,0x00,0x00,0x00,0x00,0x00,0x00,(uint8)message.size(),0x52,0x00,0x00,0x00};
		//stdout.printf("\n----\nMessage send: %s\n",message);
		conn.send (header);
		conn.send (message.data);
		return 0;
	}
	public string json_receive(GLib.Socket conn){//Принимает JSON сообщение видеорегистратора обрезая заголовок протокола
		uchar ret[12];
		uint64 payloadLen;
		uint8 buffer[100000];
		string resp;
		//do{
			conn.receive(buffer);
			stdout.printf("\nHeader:");
			for(uint j=0;j<headerLen;j=j+1){
					ret[j]=buffer[j];
					stdout.printf("%p ",(string)buffer[j]);
			}
		//}while(ret[1]==0x16);
		payloadLen = ret[7] + ret[6]*0x100 + ret[5]*0x10000 + ret[4]*0x1000000;
		resp = (string)buffer[headerLen:payloadLen+headerLen];
		stdout.printf("PayloadLen: %" + uint64.FORMAT + "\n",payloadLen);
		if((ret[0]==0x8)&&(ret[1]==0x6)) return "jpeg";//По заголовку определяестя
		if((ret[0]==0x8)&&(ret[1]==0x2)) return "h264";//JPEG или H264 data
		//if(ret[0]==0x00) return "empty";
		if ((ret[0]!=0x8)||(ret[1]==0x16)) return "error";
		return resp;
	}

	public int media_server()  {  //Сервер, принимающий видеоданные и снапшоты.

		string response = "";
		string ses = "";
		uint8 buffer[2000000];
		Response r = new Response("",0);
		/*Socket server creation*/
		InetAddress server_address = new InetAddress.from_string (localhost);
		InetSocketAddress address = new InetSocketAddress (server_address, media_port);
		stdout.puts("----------media_server--------------\n");
		GLib.Socket socket = new GLib.Socket (GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
		assert (socket != null);
		socket.bind (address, true);
		socket.set_listen_backlog (10);
		socket.listen ();
		GLib.Socket connection = socket.accept ();
		/*Open Files*/
		var file = File.new_for_path ("out.h264");
		var jpeg_file = File.new_for_path ("snap.jpeg");
		if (file.query_exists ()) {
				file.delete ();
		}
		if (jpeg_file.query_exists ()) {
				jpeg_file.delete ();
		}
		var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
		var jpeg_dos = new DataOutputStream (jpeg_file.create (FileCreateFlags.REPLACE_DESTINATION));
		long written = 0;

	  response = json_receive(connection);
	  stdout.printf("Response:%s\n",response);
		/*
			*Парсинг SESSION из response
		*/
	  try{
			var parser = new Json.Parser ();
	  	parser.load_from_data (response,response.length);
	  	Json.Node node = parser.get_root ();
	  	ses = node.get_object ().get_string_member ("SESSION");
		}catch(Error e){
			stdout.printf("\nMServer > Error: %s\n", e.message);
		}
	  string create = @"{\"MODULE\":\"CERTIFICATE\",\"OPERATION\":\"CREATESTREAM\",\"PARAMETER\":{\"ERRORCODE\":0,\"ERRORCAUSE\":\"SUCCESS\"},\"SESSION\":\"$ses\"}\r\n";
		//string controlstream = @"{\"MODULE\":\"MEDIASTREAMMODEL\",\"OPERATION\":\"CONTROLSTREAM\",\"PARAMETER\":{\"SSRC\":0,\"STREAMTYPE\":0,\"PT\":2,\"STREAMNAME\":\"STREAM-9\",\"CMD\":\"2\"},\"SESSION\":\"$ses\"}\r\n";
		//string ctrlsingleormul = @"{\"MODULE\":\"MEDIASTREAMMODEL\",\"OPERATION\":\"CTRLSINGLEORMUL\",\"PARAMETER\":{\"CSRC\":\"R\",\"CMD\":0,\"PT\":2,\"STREAMNAME\":\"STREAM-9\",\"CHMASK\":1,\"SRCCH\":\"0\",\"DESCH\":\"0\"},\"SESSION\":\"$ses\"}\r\n";
		json_send(create,connection);//Регистрация Медиа-сервера
		/**
			*Медиа-сервер ожидает пока видеорегистратор пришлет на server результат регистрации
		*/
		while(wait == true){
			json_send(create,connection);
		}
		if(start == true){
			stdout.printf("\nMedia Start-----------\n");
			try{
				response = json_receive(connection);
			}catch(Error e){
				stdout.printf("\nMServer > Error: %s\n", e.message);
			}
			for(int i=0;(i<4)&&(response=="error");i++){
				response = json_receive(connection);
				stdout.printf("MServer > Response 2:%s\n",response);
			}while(response=="error");

			if(response=="jpeg"){
				do {
					r= jpeg_receive(connection,buffer);
					while(r.resp=="header"){
						r = jpeg_receive(connection,buffer);
					}
					stdout.printf("JPEG:%s\n",(string)buffer);
					stdout.printf ("Buffer len: %" + size_t.FORMAT + "\n", r.len);
					if(r.len == 0) return 0;
		      while (written < r.len) {
		          if (r.resp == "jpeg_header") {
								written += jpeg_dos.write (buffer[16:r.len]);
								r.resp = "";
							}
							written += jpeg_dos.write (buffer[written:r.len]);
		      }
					written = 0;
				} while (r.resp != "jpeg_end");
			}
			/*
				*Принятие и парсинг h264 данных
			*/
			if(response=="h264"){
				address = new InetSocketAddress (server_address, 5558);
				Socket vsocket = new Socket (SocketFamily.IPV4, SocketType.STREAM, SocketProtocol.TCP);
				assert (vsocket != null);
				vsocket.connect (address);
				//vsocket.set_timeout(1);
				while(true){
					r= h264_receive(connection,buffer);
					while(r.resp=="header"){
						r = h264_receive(connection,buffer);
					}
					stdout.printf("DATA:%s\n",(string)buffer);
					stdout.printf ("Buffer len: %" + size_t.FORMAT + "\n", r.len);
					if(r.len == 0) return 0;
					uint8 len[10];
					Posix.memcpy(len,&r.len,sizeof(size_t));
					try{
							vsocket.send (len);
							vsocket.send (buffer);}
					catch(Error e){
						stdout.printf("\nMServer > Error: %s\n", e.message);
					}
		      while (written < r.len) {
		          written += dos.write (buffer[written:r.len]);
		      }
					written = 0;
					stdout.puts("Receive h.264 data\n");
				}
			}
		}
		stdout.printf("--------Media server close-----------\n");
		wait = true;
		connection.close();
		dos.close();
		return 0;
	}

	public int server () {//Сервер к которому подключается видеорегистратор
		/*Сокет серера комманд*/
		InetAddress server_address = new InetAddress.from_string (localhost);
		InetSocketAddress address = new InetSocketAddress (server_address, 5556);//Порт задается в настройках видеорегистратора
		stdout.puts("----------server--------------\n");
		GLib.Socket socket = new GLib.Socket (GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
		assert (socket != null);
		socket.bind (address, true);
		socket.set_listen_backlog (10);
		socket.listen ();
		GLib.Socket connection = socket.accept ();
		/*Парсинг ответа*/
		var parser = new Json.Parser ();
		Json.Node node;
		string response = "";
		string ses="",dsno,pro,operation="";
		string s0;
		do{
			response = json_receive(connection);
			stdout.printf("Response:%s\n",response);
		}while(response=="error");
		try{
	    parser.load_from_data (response,response.length);
	    node = parser.get_root ();
			ses = node.get_object ().get_string_member ("SESSION");
			var parameter = node.get_object ().get_object_member ("PARAMETER");
			dsno = parameter.get_string_member("DSNO");
			pro = parameter.get_string_member ("PRO");
			stdout.printf("Session:%s\n",ses);
			stdout.printf("DSNO:%s\n",dsno);
			stdout.printf("PRO:%s\n",pro);
		}catch(Error e){
			stdout.printf("\nServer > Error: %s\n", e.message);
		}

		//string reboot = @"{\"MODULE\":\"DISCOVERY\",\"OPERATION\":\"REBOOT\",\"SESSION\":\"$ses\"}\r\n";
		string keepalive = @"{\"MODULE\":\"CERTIFICATE\",\"OPERATION\":\"KEEPALIVE\",\"SESSION\":\"$ses\"}\r\n";
		string connect = @"{\"MODULE\":\"CERTIFICATE\",\"OPERATION\":\"CONNECT\",\"RESPONSE\":{\"SO\":\"1234\",\"ERRORCODE\":0,\"ERRORCAUSE\":\"1\"},\"SESSION\":\"$ses\"}\r\n";
		string requestalivevideo = @"{\"MODULE\":\"MEDIASTREAMMODEL\",\"OPERATION\":\"REQUESTALIVEVIDEO\",\"PARAMETER\":{\"CHANNEL\":1,\"SERIAL\":0,\"STREAMTYPE\":0,\"IPANDPORT\":\"$localhost:5557\",\"STREAMNAME\":\"STREAM-9\",\"AUDIOVALID\":2},\"SESSION\":\"$ses\"}\r\n";
		//string controlstream = @"{\"PARAMETER\":{\"SSRC\":0,\"STREAMTYPE\":0,\"PT\":2,\"STREAMNAME\":\"STREAM-9\",\"CMD\":\"0\"},\"OPERATION\":\"CONTROLSTREAM\",\"SESSION\":\"$ses\",\"MODULE\":\"MEDIASTREAMMODEL\"}\r\n";
		//string getcalendar = @"{\"PARAMETER\":{\"FILETYPE\":65535,\"CHANNEL\":4294967295,\"CALENDARTYPE\":2,\"SERIAL\":0,\"STREAMTYPE\":1},\"OPERATION\":\"GETCALENDAR\",\"SESSION\":\"$ses\",\"MODULE\":\"STORM\"}\r\n";
		//string ctrlsingleormul = @"{\"MODULE\":\"MEDIASTREAMMODEL\",\"OPERATION\":\"CTRLSINGLEORMUL\",\"PARAMETER\":{\"CSRC\":\"\",\"CMD\":0,\"PT\":2,\"STREAMNAME\":\"STREAM-9\"},\"SESSION\":\"$ses\"}\r\n";//,\"CHMASK\":8,\"SRCCH\":\"8\",\"DESCH\":\"8\"
		//\"CSRC\":\"0x52\",\"SSRC\":0,,\"PRETIME\":0,\"Q\":1,\"S\":\"INTERVAL\":2,\"FREAMCOUNT\":1,\"FREAMINTERVAL\":1,\"SENDMODE\":0,
		json_send(connect,connection);//Регистрация
		json_receive(connection);
		int channel=2;
			//string requestcatchpic = @"{\"MODULE\":\"MEDIASTREAMMODEL\",\"OPERATION\":\"REQUESTCATCHPIC\",\"PARAMETER\":{\"SSRC\":1,\"CHANNEL\":$channel,\"IPANDPORT\":\"10.0.0.3:5557\",\"CMDTYPE\":0,\"STREAMNAME\":\"STREAM-9\",\"PRETIME\":0,\"COUNT\":1,\"FORMAT\":1,\"R\":0},\"SESSION\":\"$ses\"}\r\n";
			//json_send(requestcatchpic,connection);
			requestalivevideo = @"{\"MODULE\":\"MEDIASTREAMMODEL\",\"OPERATION\":\"REQUESTALIVEVIDEO\",\"PARAMETER\":{\"CHANNEL\":$channel,\"SERIAL\":0,\"STREAMTYPE\":0,\"IPANDPORT\":\"$localhost:$media_port\",\"STREAMNAME\":\"STREAM-9\",\"AUDIOVALID\":2},\"SESSION\":\"$ses\"}\r\n";
			json_send(requestalivevideo,connection);
		do{
			operation = " ";
			do{
				response = json_receive(connection);
				stdout.printf("Server > 3 Response:%s\n",response);
			}while(response=="error");
			try{
				parser.load_from_data (response,response.length);
				node = parser.get_root ();
				operation = node.get_object().get_string_member("OPERATION");
				stdout.printf("operation: %s\n",operation);
			} catch (Error e){
				stdout.printf("\nServer > Error: %s\n", e.message);
			}
			if(operation=="KEEPALIVE"){//Heart beat
				json_send(keepalive,connection);
			}
			if(operation=="MEDIATASKSTOP"){
				start = false;
				wait=false;
				//json_send(requestcatchpic,connection);
				json_send(requestalivevideo,connection);
			}
			if(operation=="MEDIATASKSTART"){
				wait = false;
				start = true;
			}
			/*if(operation=="MEDIATASKSTART"){
				Thread.usleep(100000);
				response = json_receive(connection);
				json_send(controlstream,connection);
				do{
					response = json_receive(connection);
					stdout.printf("5 Response:%s\n",response);
				}while(response=="error");
				json_send(ctrlsingleormul,connection);
				do{
					response = json_receive(connection);
					stdout.printf("6 Response:%s\n",response);
				}while((response=="error")||(response=="empty"));
			}*/
		}while(true);
		connection.close();
		stdout.puts("\n---------------------------------------------------------------------------------------------------------------\n");
		return 0;
	}
}

public static int main (string[] args) {
	if (!Thread.supported()) {
			stderr.printf("Cannot run without threads.\n");
			return 1;
	}
	try{
		int result = 0;
		MyServer my_thread = new MyServer ();
		Thread<int> server_thread = new Thread<int>.try("server",my_thread.server);
		do{
			Thread<int> media_server_thread = new Thread<int>.try("media_server",my_thread.media_server);
			// Wait until thread finishes:
			result = media_server_thread.join ();
			stdout.printf ("Thread media_server stopped! Return value: %d\n", result);
		}while(result == 0);
		result = server_thread.join ();
		// Output: `Thread stopped! Return value: 42`
		stdout.printf ("Thread stopped! Return value: %d\n", result);
	}catch(Error e){
		stdout.printf ("Error: %s\n", e.message);
	}
	return 0;
}
