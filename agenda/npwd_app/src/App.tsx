import React, { useEffect, useRef } from 'react';
import { useHistory } from 'react-router-dom';

const AgendaApp: React.FC = () => {
  const history = useHistory();
  const iframeRef = useRef<HTMLIFrameElement>(null);

  // Quand l'iframe est prête : récupère la config depuis Lua et l'envoie à l'iframe
  const onIframeLoad = () => {
    fetch('https://agenda/getBusinesses', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    })
      .then(r => r.json())
      .catch(() => ({}))
      .then((data: any) => {
        iframeRef.current?.contentWindow?.postMessage(
          { action: 'open', businesses: data.businesses || {} },
          '*',
        );
      });
  };

  useEffect(() => {
    // Écoute le message de fermeture depuis l'iframe agenda
    const handler = (event: MessageEvent) => {
      if (event.data?.type === 'agenda:close') {
        history.push('/');
      }
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, [history]);

  return (
    <iframe
      ref={iframeRef}
      src="https://agenda/html/index.html"
      onLoad={onIframeLoad}
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width: '100%',
        height: '100%',
        border: 'none',
        display: 'block',
      }}
    />
  );
};

export default AgendaApp;
