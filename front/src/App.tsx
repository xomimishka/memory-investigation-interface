import { useState } from "react";
import axios from "axios";

function App() {
  const [user, setUser] = useState("");
  const [events, setEvents] = useState<any[]>([]);

  async function search() {
    const res = await axios.post("http://localhost:8080/search", {
      user,
    });

    setEvents(res.data);
  }

  return (
    <div>
      <input
        value={user}
        onChange={(e) => setUser(e.target.value)}
        placeholder="Введите user"
      />

      <button onClick={search}>Поиск</button>

      {events.map((item, index) => (
        <div key={index}>
          <b>Совпадение: {item.score}%</b>
          <pre>{JSON.stringify(item.event, null, 2)}</pre>
        </div>
      ))}
    </div>
  );
}

export default App;