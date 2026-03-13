document.addEventListener('DOMContentLoaded', () => {
    const tabs = document.querySelectorAll('.tab-link');
    const captureContent = document.getElementById('capture-content');
    const browseContent = document.getElementById('browse-content');
    const token = sessionStorage.getItem('token');

    if (!token) {
        window.location.href = '/';
        return;
    }

    function showMessage(message, isError = false) {
        const outputElement = document.getElementById('output');
        outputElement.style.display = 'block';
        outputElement.style.color = isError ? 'red' : 'black';
        outputElement.innerText = message;
    }

    function hideMessage() {
        const outputElement = document.getElementById('output');
        outputElement.style.display = 'none';
        outputElement.innerText = '';
    }

    async function apiFetch(url, options = {}) {
        const response = await fetch(url, {
            ...options,
            headers: {
                'Authorization': `Bearer ${sessionStorage.getItem('token')}`,
                ...(options.headers || {})
            }
        });

        if (response.status === 401 || response.status === 403) {
            sessionStorage.removeItem('token');
            window.location.href = '/';
            throw new Error('Authentication required');
        }

        return response;
    }

    async function refreshCaptureList() {
        hideMessage();

        const nofile = document.getElementById('no_file');
        const fileList = document.getElementById('folder');

        nofile.style.display = 'none';
        fileList.innerHTML = '';

        try {
            const response = await apiFetch('/api/v1/captures');
            const result = await response.json();

            if (!response.ok || !result.success) {
                throw new Error(result.error || 'Failed to list captures');
            }

            const files = Array.isArray(result.data.files) ? result.data.files : [];

            if (files.length === 0) {
                nofile.style.display = 'block';
                fileList.appendChild(nofile);
                return;
            }

            files.forEach(file => {
                const fileDiv = document.createElement('div');
                fileDiv.classList.add('file-container');

                const listItem = document.createElement('p');
                listItem.classList.add('file-name');
                listItem.textContent = file;

                const btnDownload = document.createElement('button');
                btnDownload.classList.add('btn-file-download');
                btnDownload.addEventListener('click', () => downloadFile(file));

                const downloadItem = document.createElement('span');
                downloadItem.classList.add('file-download');

                btnDownload.appendChild(downloadItem);
                fileDiv.appendChild(listItem);
                fileDiv.appendChild(btnDownload);
                fileList.appendChild(fileDiv);
            });
        } catch (error) {
            nofile.style.display = 'block';
            fileList.appendChild(nofile);
            showMessage(error.message || String(error), true);
        }
    }

    async function launchCapture() {
        const button = document.getElementById('submit-btn');
        const data = {
            filename: document.getElementById('filename').value.trim(),
            format: document.getElementById('format').value,
            time_delay: Number(document.getElementById('time_delay').value),
            unit_delay: document.getElementById('delay_format').value
        };

        button.disabled = true;
        button.style.opacity = '0.5';
        button.style.cursor = 'not-allowed';
        button.innerText = 'Capture in progress...';
        hideMessage();

        try {
            const response = await apiFetch('/api/v1/captures', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(data)
            });

            const result = await response.json();

            if (!response.ok || !result.success) {
                throw new Error(result.error || 'Capture failed');
            }

            showMessage(result.message || 'Capture completed successfully');
        } catch (error) {
            showMessage(error.message || String(error), true);
        } finally {
            button.disabled = false;
            button.style.opacity = '1';
            button.style.cursor = 'pointer';
            button.innerText = 'Launch Capture';
        }
    }

    async function logout() {
        try {
            await apiFetch('/api/v1/auth/logout', {
                method: 'POST'
            });
        } catch (error) {
            // ignore logout error, client-side cleanup still happens
        } finally {
            sessionStorage.removeItem('token');
            window.location.href = '/';
        }
    }

    async function downloadFile(filename) {
        hideMessage();

        try {
            const response = await apiFetch(`/api/v1/captures/${encodeURIComponent(filename)}/download`);

            if (!response.ok) {
                let result = null;
                try {
                    result = await response.json();
                } catch (_) {}
                throw new Error(result?.error || 'Download failed');
            }

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
            showMessage(error.message || String(error), true);
        }
    }

    function showActiveTab() {
        const activeTab = document.querySelector('.tab-link.active').dataset.tab;

        if (activeTab === 'capture') {
            captureContent.style.display = 'block';
            browseContent.style.display = 'none';
        } else if (activeTab === 'browse') {
            refreshCaptureList();
            captureContent.style.display = 'none';
            browseContent.style.display = 'block';
        }
    }

    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            tabs.forEach(t => t.classList.remove('active'));
            tab.classList.add('active');
            showActiveTab();
        });
    });

    document.getElementById('submit-btn').addEventListener('click', launchCapture);
    document.getElementById('logout').addEventListener('click', logout);

    showActiveTab();
});