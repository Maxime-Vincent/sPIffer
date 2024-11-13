document.addEventListener('DOMContentLoaded', () => {
  const tabs = document.querySelectorAll('.tab-link');
  const captureContent = document.getElementById('capture-content');
  const browseContent = document.getElementById('browse-content');

  function showActiveTab() {
    const activeTab = document.querySelector('.tab-link.active').dataset.tab;
    if (activeTab === 'capture') {
      captureContent.style.display = 'block';
      browseContent.style.display = 'none';
    } else if (activeTab === 'browse') {
      get_captures_file()
      captureContent.style.display = 'none';
      browseContent.style.display = 'block';
    }
  }

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      // Delete 'active' state for tab
      tabs.forEach(t => t.classList.remove('active'));
      // Add 'active' state for tab
      tab.classList.add('active');
      // Display/Hide the tabs
      showActiveTab();
    });
  });

  showActiveTab();
  document.getElementById('submit-btn').addEventListener('click', launch_capture);
  document.getElementById('logout').addEventListener('click', logout);
});

// Send POST request for capture files
async function get_captures_file() {
  const outputElement = document.getElementById("output");
  outputElement.style.display = "none";
  try {
    const response = await fetch('/browsefiles', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    });
    const result = await response.json();
    if (result.Error) {
      throw new Error(result.Error);
    }
    const files = Array.isArray(JSON.parse(result.Files)) ? JSON.parse(result.Files) : [];
    const fileList = document.getElementById("folder");
    fileList.innerHTML = "";

    files.forEach(file => {
      const file_div = document.createElement("div");
      file_div.classList.add("file-container");

      const listItem = document.createElement("p");
      listItem.classList.add("file-name");
      listItem.textContent = file;

      const btn_download = document.createElement("button");
      btn_download.classList.add("btn-file-download");
      btn_download.addEventListener("click", () => download_file(file));
      const downloadItem = document.createElement("span");
      downloadItem.classList.add("file-download");

      file_div.appendChild(listItem);
      btn_download.appendChild(downloadItem);
      file_div.appendChild(btn_download);
      fileList.appendChild(file_div);
    });
  } catch (error) {
    outputElement.style.display = "block";
    outputElement.style.color = "red";
    outputElement.innerText = error;
  }
}

// Method to launch capture
async function launch_capture() {
  const button = document.getElementById("submit-btn");
  button.disabled = true;
  button.style.opacity = "0.5";
  button.style.cursor = "not-allowed";
  button.innerText = "Capture in progress...";
  const outputElement = document.getElementById("output");
  outputElement.style.display = "none";
  const data = {
    filename: document.getElementById("filename").value,
    format: document.getElementById("format").value,
    time_delay: document.getElementById("time_delay").value,
    unit_delay: document.getElementById("delay_format").value
  };
  try {
    const response = await fetch('/launch_capture', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(data)
    });
    const result = await response.json();
    outputElement.style.color = "black";
    outputElement.style.display = "block";
    if (result.Info) {
      outputElement.innerText = result.Info;
    } else {
      throw new Error(result.Error);
    }
  } catch (error) {
    outputElement.style.display = "block";
    outputElement.style.color = "red";
    outputElement.innerText = error;
  } finally {
    button.disabled = false;
    button.style.opacity = "1";
    button.style.cursor = "pointer";
    button.innerText = "Launch Capture";
  }
}
// Method for disconnection
async function logout() {
  try {
    const response = await fetch('/logout', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    });
    if (response.ok) {
      // Redirection after disconnection
      window.location.href = '/';
    } else {
      console.error('Disconnection error');
    }
  } catch (error) {
    console.error('Network error during disconnection:', error);
  }
}

async function download_file(filename) {
  data = {
    filecap: filename
  };
  try {
    console.log(filename);
    const response = await fetch('/download_capture', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(data)
    });
    // Create a blob
    const blob = await response.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
  } catch (error) {
    console.error('Network error:', error);
  }
}