document.addEventListener('DOMContentLoaded', () => {
    const tabs = document.querySelectorAll('.tab-link');
    const captureContent = document.getElementById('capture-content');
    const browseContent = document.getElementById('browse-content');
    const outputElement = document.getElementById('output');
    const nofile = document.getElementById('no_file');
    const fileList = document.getElementById('folder');
    const submitButton = document.getElementById('submit-btn');
    const token = sessionStorage.getItem('token');

    if (!token) {
        window.location.href = '/';
        return;
    }

    function showElement(element) {
        element.classList.remove('hidden');
    }

    function hideElement(element) {
        element.classList.add('hidden');
    }

    function showMessage(message, isError = false) {
        outputElement.textContent = message;
        outputElement.classList.remove('message-error', 'message-success');
        outputElement.classList.add(isError ? 'message-error' : 'message-success');
        showElement(outputElement);
    }

    function hideMessage() {
        outputElement.textContent = '';
        outputElement.classList.remove('message-error', 'message-success');
        hideElement(outputElement);
    }

    function setCaptureButtonBusy(isBusy) {
        submitButton.disabled = isBusy;
        submitButton.classList.toggle('is-disabled', isBusy);
        submitButton.textContent = isBusy ? 'Capture in progress...' : 'Launch Capture';
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
        hideElement(nofile);
        fileList.innerHTML = '';

        try {
            const response = await apiFetch('/api/v1/captures');
            const result = await response.json();

            if (!response.ok || !result.success) {
                throw new Error(result.error || 'Failed to list captures');
            }

            const files = Array.isArray(result.data.files) ? result.data.files : [];

            if (files.length === 0) {
                showElement(nofile);
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
            showElement(nofile);
            fileList.appendChild(nofile);
            showMessage(error.message || String(error), true);
        }
    }

    async function launchCapture() {
        const data = {
            filename: document.getElementById('filename').value.trim(),
            format: document.getElementById('format').value,
            time_delay: Number(document.getElementById('time_delay').value),
            unit_delay: document.getElementById('delay_format').value
        };

        setCaptureButtonBusy(true);
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
            setCaptureButtonBusy(false);
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
            showElement(captureContent);
            hideElement(browseContent);
        } else if (activeTab === 'browse') {
            hideElement(captureContent);
            showElement(browseContent);
            refreshCaptureList();
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