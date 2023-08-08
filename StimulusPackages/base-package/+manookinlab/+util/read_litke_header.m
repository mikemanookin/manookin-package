function file_name = read_litke_header(input)
    import java.io.*;
    stream = DataInputStream(input);
    tagsLeft = true;
    while (tagsLeft)
        tag = stream.readInt();
        tag_length = stream.readInt();
        switch (tag)
            case 0
                headerLength = stream.readInt();
                break;
            case 1
                timeBase = stream.readInt();
                secondsTime = stream.readLong();
        end
    end
end