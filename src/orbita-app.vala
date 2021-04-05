using Orbita;

/*
 * Коммуникационный поток для асинхронной очереди.
 * Соответственно, поток с writing_func - сервер декодер n9m принимает пакеты,
 * забирает из заголовка номер канала, PAYLOAD копирует в буфер VO и кладет в
 * асинхронную очередь.
 * Поток с reading_func - GStreamer-овский поток, забирает из асинхронной очереди
 * VO и отдает на конвеер на воспроизведение.
 * */
class ThreadCommunication {

    private const int NUMBER_OF_MESSAGES = 200000; /*тестовое значение, если
    придется передергивать соединение с видеорегистратором, то можно поставить
    какое то разумное значение, либо задать количество принятых кадров до момента
    отправки KeepAlive
    */

   /*
    * Асинхронная очередь, предназначена для хранения видеокадров.
    * В дальнейшем надо будет заменить на инмемори базу данных.
    * */
    private AsyncQueue<DataBox> async_queue;

	/*
	 * Конструктор, инициализирует очередь
	 * */
    public ThreadCommunication () {
        this.async_queue = new AsyncQueue<DataBox> ();
    }

    //TODO: расширить VO(ValueObject) для отправки видеокадров
    /*
     * Класс обертка для данных, помещаемых в асинхронную очередь
     * */
    private class DataBox {

        public int number { get; private set; }  // порядковый номер пакета
        public string name { get; private set; } // номер канала / наименование канала / время / активность или НЕТ СИГНАЛА
        //TODO: добавить буфер и его длину

        public DataBox (int number, string name) {
            this.number = number;
            this.name = name;
        }
    }

	/**
	 * Функция записи данных в очередь.
	 * */
    private void* writing_func () {
        var timer = new Timer ();
        timer.start ();
		//TODO: нужно понять пригодится ли нам этот таймер для отметки времени кадра в GSTBuffer,
		// если не пригодится - то удалить.
		// Другой вариант использования - отправка KeepAlive через временные интервалы, а не считать принятые
		// кадры.

		//TODO: сюда вставить инициализацию нашего видеосервера.
		// цикл на чтение из сокета данных в формате n9m присылаемых видеорегистратором
        for (int i = 0; i < NUMBER_OF_MESSAGES; i++) {
            // подготовка пакета для отправки
            var databox = new DataBox (i, @"some text for value $i");

            //TODO: копирование принятых данных в буфер databox.

            // отправка пакета в очередь
            async_queue.push (databox);
        }
        //TODO: поставить обработчик, если что-то будем делать по времени
        print ("Отправлено %d кадров в AsyncQueue зв %f сек.\n", NUMBER_OF_MESSAGES, timer.elapsed ());
        return null;
    }

    private void* reading_func () {
        var timer = new Timer ();
        timer.start ();
                timer.start ();
		//TODO: нужно понять пригодится ли нам этот таймер для отметки времени кадра в GSTBuffer,
		// если не пригодится - то удалить.
		// Другой вариант использования - мониторинг, что мы не подвисли, либо канал (один или несколько) не подвис
        for (int i = 0; i < NUMBER_OF_MESSAGES; i++) {
            // получаем пакет из асинхронной очереди
            var databox = async_queue.pop ();

            // проверяем на целостность содержимого,
            // после отладки можно будет убрать. Пока не будет уверенности, что мы ничего не теряем - оставляем.
            assert (i == databox.number);



            // показываем отладочную информацию
            if ((NUMBER_OF_MESSAGES / 2) == databox.number) {
                print ("\tNO: %d \tTEXT: %s\n", databox.number, databox.name);
            }
        }
        // показываем отладочную информацию. Если будем обрабатывать зависание канала - то сюда встраиваем обработчик.
        print ("Получено %d пакетов из AsyncQueue за %f сек.\n", NUMBER_OF_MESSAGES, timer.elapsed ());
        return null;
    }

	/**
	 * Функция основного потока
	 * В дальнейшем ее будем вызывать из потока приложения (у нас был менеджер написан, можно в него встроить контроль)
	 * */
    public void run () {
        try {
            unowned Thread<void*> thread_a = Thread.create<void*> (writing_func, true);
            unowned Thread<void*> thread_b = Thread.create<void*> (reading_func, true);

            // Ждем завершения потоков
            thread_a.join ();
            thread_b.join ();

        } catch (ThreadError e) {
            stderr.printf ("%s\n", e.message);
            return;
        }
    }
}

void main () {
    var thread_comm = new ThreadCommunication ();
    thread_comm.run ();
}
