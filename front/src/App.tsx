import { useState } from "react";
import axios from "axios";

function App() {
  const [user, setUser] = useState("");
  const [fileName, setFileName] = useState("");
  const [action, setAction] = useState("");
  const [destinationType, setDestinationType] = useState("");

  const [events, setEvents] = useState<any[]>([]);

  async function search() {
    const res = await axios.post("http://localhost:8080/search", {
      hints: {
        user_id: user,
        file_name: fileName,
        action: action,
        destination_type: destinationType,
      },
    });

    setEvents(res.data.candidates);
  }

  return (
    <div>
      <input
        value={user}
        onChange={(e) => setUser(e.target.value)}
        placeholder="User ID"
      />

      <input
        value={fileName}
        onChange={(e) => setFileName(e.target.value)}
        placeholder="File name"
      />

      <input
        value={action}
        onChange={(e) => setAction(e.target.value)}
        placeholder="Action"
      />

      <input
        value={destinationType}
        onChange={(e) => setDestinationType(e.target.value)}
        placeholder="Destination type"
      />

      <button onClick={search}>Поиск</button>

      {events.map((item: any) => (
        <div key={item.event.event_id}>
          <div>Score: {item.score}</div>

          <div>
            Совпадения: {item.matched_hints.join(", ")}
          </div>

          <pre>{JSON.stringify(item.event, null, 2)}</pre>
        </div>
      ))}
    </div>
  );
}

export default App;