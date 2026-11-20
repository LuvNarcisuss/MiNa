import React, {useCallback, useEffect, useRef, useState} from 'react';
import {ActivityIndicator, NativeModules, Pressable, StatusBar, StyleSheet, Text, View} from 'react-native';
import {WebView, type WebViewMessageEvent} from 'react-native-webview';

type Entry = {entry: string; root: string};
type NativeBridge = {
  prepare(): Promise<Entry>;
  invoke(method: string, params: Record<string, unknown>): Promise<unknown>;
};

const native: NativeBridge = NativeModules.MiNaNative;
const commands = new Set([
  'getSession', 'setSession', 'loadState', 'saveState', 'clearLocalData',
  'startRecording', 'stopRecording', 'recoverRecording', 'playRecording',
  'stopPlayback', 'playbackStatus', 'setCallSpeaker', 'pickMedia', 'resolveMedia', 'mediaBytes', 'deleteMedia',
  'setStatusBarStyle', 'showPolicy', 'getCatalog', 'purchase', 'companionStatus', 'companionReply',
]);

export default function App() {
  const [entry, setEntry] = useState<Entry | null>(null);
  const [lightStatusBar, setLightStatusBar] = useState(true);
  const [problem, setProblem] = useState('');
  const [attempt, setAttempt] = useState(0);
  const page = useRef<WebView>(null);
  const epoch = useRef(0);
  const pending = useRef(new Set<string>());
  const completed = useRef(new Set<string>());

  useEffect(() => {
    let active = true;
    setEntry(null);
    setProblem('');
    native.prepare().then(result => {
      if (active) setEntry(result);
    }).catch(error => {
      if (active) setProblem(error.message || 'The bedtime pages could not be opened.');
    });
    return () => { active = false; };
  }, [attempt]);

  const invalidate = useCallback(() => {
    epoch.current += 1;
    pending.current.clear();
    completed.current.clear();
    setLightStatusBar(true);
  }, []);

  const fail = useCallback((message: string) => {
    invalidate();
    setProblem(message);
  }, [invalidate]);

  const onMessage = useCallback(async (event: WebViewMessageEvent) => {
    const {url, data} = event.nativeEvent;
    if (!entry || url.split('#')[0] !== entry.entry || typeof data !== 'string' || data.length > 9 * 1024 * 1024) return;
    let request: {id?: unknown; method?: unknown; params?: unknown};
    try { request = JSON.parse(data); } catch { return; }
    if (!request || typeof request.id !== 'string' || !/^[\w.-]{1,96}$/.test(request.id)) return;
    const {id, method, params = {}} = request;
    if (pending.current.has(id)) return;
    const revision = epoch.current;
    let response: {id: string; result?: unknown; error?: string};
    try {
      if (completed.current.has(id)) throw new Error('This request has already finished.');
      if (pending.current.size >= 64) throw new Error('Please wait for the other requests to finish.');
      pending.current.add(id);
      if (typeof method !== 'string' || !commands.has(method) || !params || typeof params !== 'object' || Array.isArray(params)) {
        throw new Error('This action is unavailable.');
      }
      const values = params as Record<string, unknown>;
      if (method === 'setStatusBarStyle') {
        if (typeof values.light !== 'boolean') throw new Error('Choose a valid status bar appearance.');
        setLightStatusBar(values.light);
        response = {id, result: {light: values.light}};
      } else {
        response = {id, result: await native.invoke(method, values)};
      }
    } catch (error) {
      response = {id, error: error instanceof Error ? error.message : 'The action could not be completed.'};
    }
    if (revision === epoch.current) {
      if (pending.current.delete(id)) {
        completed.current.add(id);
        if (completed.current.size > 512) {
          const oldest = completed.current.values().next().value;
          if (oldest !== undefined) completed.current.delete(oldest);
        }
      }
      const detail = JSON.stringify(response).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
      page.current?.injectJavaScript(`window.dispatchEvent(new CustomEvent('mina:native',{detail:${detail}}));true;`);
    }
  }, [entry]);

  if (!entry || problem) {
    return <View style={styles.status}>
      <StatusBar barStyle="light-content" />
      <Text style={styles.title}>MiNa</Text>
      {problem ? <>
        <Text accessibilityLiveRegion="polite" style={styles.message}>{problem}</Text>
        <Pressable style={styles.retry} onPress={() => setAttempt(n => n + 1)} accessibilityRole="button">
          <Text style={styles.retryLabel}>Try again</Text>
        </Pressable>
      </> : <ActivityIndicator accessibilityLabel="Opening MiNa" color="#96ffe5" />}
    </View>;
  }

  return <View style={styles.shell}>
    <StatusBar barStyle={lightStatusBar ? 'light-content' : 'dark-content'} />
    <WebView
      key={attempt}
      ref={page}
      style={styles.page}
      source={{uri: entry.entry}}
      allowingReadAccessToURL={entry.root}
      originWhitelist={['*']}
      onShouldStartLoadWithRequest={request => request.url.split('#')[0] === entry.entry}
      onOpenWindow={() => {}}
      onLoadStart={invalidate}
      onMessage={onMessage}
      onError={() => fail('MiNa could not open its bedtime pages.')}
      onContentProcessDidTerminate={() => fail('The pages closed unexpectedly. Reopen MiNa to continue.')}
      javaScriptEnabled
      domStorageEnabled
      allowsInlineMediaPlayback
      mediaPlaybackRequiresUserAction={false}
      mediaCapturePermissionGrantType="prompt"
      allowsLinkPreview={false}
      automaticallyAdjustContentInsets={false}
      contentInsetAdjustmentBehavior="never"
      bounces={false}
      allowsBackForwardNavigationGestures={false}
      setSupportMultipleWindows={false}
    />
  </View>;
}

const styles = StyleSheet.create({
  shell: {flex: 1, backgroundColor: '#e2fff6'},
  page: {flex: 1, backgroundColor: 'transparent'},
  status: {flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#123c51', padding: 32, gap: 20},
  title: {fontSize: 46, color: '#c5ffea', fontWeight: '700'},
  message: {fontSize: 16, lineHeight: 24, textAlign: 'center', color: '#effff9'},
  retry: {paddingHorizontal: 27, paddingVertical: 13, borderRadius: 24, backgroundColor: '#b7ffe5'},
  retryLabel: {fontSize: 16, fontWeight: '600', color: '#184738'},
});
